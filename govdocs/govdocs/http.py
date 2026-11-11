"""Polite HTTP client: per-host rate limiting, retries, robots.txt."""

import logging
import time
import urllib.robotparser
from urllib.parse import urlsplit

import requests

log = logging.getLogger(__name__)

RETRY_STATUSES = {429, 500, 502, 503, 504}


class RobotsDisallowed(Exception):
    pass


class Client:
    def __init__(self, user_agent, min_interval=1.0, max_retries=4,
                 timeout=30, session=None, sleep=time.sleep):
        self.user_agent = user_agent
        self.min_interval = min_interval
        self.max_retries = max_retries
        self.timeout = timeout
        self.session = session or requests.Session()
        self.session.headers["User-Agent"] = user_agent
        self._sleep = sleep
        self._last_hit = {}   # host -> monotonic time of last request
        self._robots = {}     # host -> RobotFileParser or None

    # -- robots.txt -------------------------------------------------------
    def _robots_for(self, url):
        parts = urlsplit(url)
        host = f"{parts.scheme}://{parts.netloc}"
        if host not in self._robots:
            rp = urllib.robotparser.RobotFileParser()
            try:
                resp = self.session.get(host + "/robots.txt", timeout=self.timeout)
                if resp.status_code == 200:
                    rp.parse(resp.text.splitlines())
                else:
                    # 4xx: no robots file, everything allowed.
                    # 5xx: be cautious, treat as allow but log it.
                    if resp.status_code >= 500:
                        log.warning("robots.txt %s returned %s", host, resp.status_code)
                    rp.parse([])
            except requests.RequestException as exc:
                log.warning("robots.txt fetch failed for %s: %s", host, exc)
                rp.parse([])
            self._robots[host] = rp
        return self._robots[host]

    def allowed(self, url):
        return self._robots_for(url).can_fetch(self.user_agent, url)

    def sitemaps(self, url):
        return self._robots_for(url).site_maps() or []

    def _crawl_delay(self, url):
        try:
            return self._robots_for(url).crawl_delay(self.user_agent)
        except Exception:
            return None

    # -- requests ---------------------------------------------------------
    def _throttle(self, url, extra_delay=None):
        host = urlsplit(url).netloc
        gap = max(self.min_interval, extra_delay or 0)
        last = self._last_hit.get(host)
        if last is not None:
            wait = gap - (time.monotonic() - last)
            if wait > 0:
                self._sleep(wait)
        self._last_hit[host] = time.monotonic()

    def get(self, url, params=None, headers=None, check_robots=False, stream=False):
        delay = None
        if check_robots:
            if not self.allowed(url):
                raise RobotsDisallowed(url)
            delay = self._crawl_delay(url)
        attempt = 0
        while True:
            self._throttle(url, delay)
            try:
                resp = self.session.get(url, params=params, headers=headers,
                                        timeout=self.timeout, stream=stream)
            except requests.RequestException as exc:
                if attempt >= self.max_retries:
                    raise
                wait = 2 ** (attempt + 1)
                log.warning("%s: %s; retry in %ss", url, exc, wait)
                self._sleep(wait)
                attempt += 1
                continue
            if resp.status_code in RETRY_STATUSES and attempt < self.max_retries:
                wait = _retry_after(resp) or 2 ** (attempt + 1)
                log.warning("%s: HTTP %s; retry in %ss", url, resp.status_code, wait)
                self._sleep(wait)
                attempt += 1
                continue
            resp.raise_for_status()
            return resp

    def get_json(self, url, params=None, headers=None):
        return self.get(url, params=params, headers=headers).json()


def _retry_after(resp):
    value = resp.headers.get("Retry-After")
    if value and value.isdigit():
        return min(int(value), 3600)
    return None
