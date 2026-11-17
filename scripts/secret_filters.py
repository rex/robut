"""detect-secrets filter: drop a Secret Keyword finding whose value is provably a reference.

KeywordDetector flags any value on a key that names a secret (``*password*``, ``*token*``), so
references to secrets (1Password item titles, ``op://`` URIs, env-var names) look like secrets
and fill the baseline with noise that trains everyone to wave findings through
(rex/homelab-ansible#24). This drops a finding only when the value itself is a reference; a
literal value is still reported, whatever its key. Entropy and provider plugins are untouched.

The baseline records it in ``filters_used``, so the pre-commit hook applies it as well. To
re-baseline: ``detect-secrets scan --baseline .secrets.baseline``.
"""

import re

# A 1Password item title in the lab's naming scheme, e.g. infra-pihole-a-homelab.
_OP_ITEM = re.compile(r"^(infra|db|svc|app|scm|ops|user|api)-[a-z0-9][a-z0-9-]*$")
# An environment-variable name, e.g. PIHOLE_A_PASSWORD.
_ENV_NAME = re.compile(r"^[A-Z][A-Z0-9_]{2,}$")
# A 1Password field name, which counts only on a key that says it holds a reference
# (e.g. postgres_op_field: password).
_FIELD = re.compile(
    r"^(password|token|secret|credential|api-key|private-key|public-key|username|database-url)$"
)
_REF_KEY = re.compile(r"_(env|ref|field|item|op_item|op_field|var|name|path|file)\s*[:=]", re.I)


def is_reference_not_secret(secret: str, line: str, plugin: object) -> bool:
    """True when a Secret Keyword finding's value is a reference to a secret, not a secret."""
    if getattr(plugin, "secret_type", "") != "Secret Keyword":
        return False
    value = secret.strip().strip("'\"")
    return bool(
        value.startswith("op://")
        or "{{" in value
        or _ENV_NAME.match(value)
        or _OP_ITEM.match(value)
        or (_FIELD.match(value) and _REF_KEY.search(line))
    )
