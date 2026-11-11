"""Minimal WordPress REST client for the media library (core wp/v2 routes).

Authenticates with an Application Password (Users > Profile > Application
Passwords in wp-admin). Nothing here deletes or edits existing media."""

import mimetypes
import os

import requests

DEFAULT_SITE = "https://granitestatereport.com"

MIME = {
    ".pdf": "application/pdf",
    ".doc": "application/msword",
    ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ".xls": "application/vnd.ms-excel",
    ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ".ppt": "application/vnd.ms-powerpoint",
    ".pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    ".odt": "application/vnd.oasis.opendocument.text",
    ".ods": "application/vnd.oasis.opendocument.spreadsheet",
    ".txt": "text/plain",
    ".csv": "text/csv",
    ".rtf": "application/rtf",
}


class WordPressError(Exception):
    pass


class WordPress:
    def __init__(self, site=None, user=None, app_password=None, session=None, timeout=120):
        self.site = (site or os.environ.get("GSR_WP_SITE") or DEFAULT_SITE).rstrip("/")
        user = user or os.environ.get("GSR_WP_USER")
        pw = app_password or os.environ.get("GSR_WP_APP_PASSWORD")
        if not user or not pw:
            raise WordPressError("Set GSR_WP_USER and GSR_WP_APP_PASSWORD "
                                 "(a WordPress Application Password) to publish.")
        self.session = session or requests.Session()
        self.session.auth = (user, pw)
        self.timeout = timeout

    def _url(self, path):
        return f"{self.site}/wp-json/wp/v2/{path}"

    def _check(self, resp):
        if resp.status_code >= 400:
            try:
                msg = resp.json().get("message", resp.text[:300])
            except ValueError:
                msg = resp.text[:300]
            raise WordPressError(f"HTTP {resp.status_code}: {msg}")
        return resp.json()

    def find_by_checksum(self, sha256):
        """Media items whose description carries this sha256 (our dedupe key)."""
        resp = self.session.get(self._url("media"), timeout=self.timeout, params={
            "search": sha256, "context": "edit", "per_page": 5,
            "_fields": "id,source_url,description"})
        items = self._check(resp)
        return [m for m in items
                if sha256 in ((m.get("description") or {}).get("raw") or "")]

    def upload(self, path, filename):
        ext = os.path.splitext(filename)[1].lower()
        mime = MIME.get(ext) or mimetypes.guess_type(filename)[0] or "application/octet-stream"
        with open(path, "rb") as fh:
            resp = self.session.post(self._url("media"), data=fh, timeout=self.timeout, headers={
                "Content-Type": mime,
                "Content-Disposition": f'attachment; filename="{filename}"'})
        return self._check(resp)

    def update(self, media_id, **fields):
        resp = self.session.post(self._url(f"media/{media_id}"), json=fields,
                                 timeout=self.timeout)
        return self._check(resp)
