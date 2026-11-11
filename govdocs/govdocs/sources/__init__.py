from .congress import Congress
from .courtlistener import CourtListener
from .crawler import Crawler
from .federal_register import FederalRegister
from .govinfo import GovInfo
from .regulations_gov import RegulationsGov

SOURCES = {cls.name: cls for cls in
           (FederalRegister, GovInfo, RegulationsGov, Congress,
            CourtListener, Crawler)}
