import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_ROOT))

from kernel.profile.engineering_pack import (  # noqa: E402
    normalize_pack,
    resolve_engineering_pack,
)

assert normalize_pack(None) == "none"
assert normalize_pack("grill") == "grill"

g = resolve_engineering_pack(profile_id="grill-pack")
assert g["engineering_pack"] == "grill"
assert g["skills_to_load"] == ["goal-engineering-grill"]

print("OK kernel.profile.engineering_pack unit")
