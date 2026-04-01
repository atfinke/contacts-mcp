const PHONE_SCHEME_PREFIX = /^(?:tel|sms):/iu;
const EMAIL_SCHEME_PREFIX = /^mailto:/iu;

export function normalizePhoneLookupInput(phoneNumber: string): string {
  const trimmed = phoneNumber.trim();
  if (!trimmed) {
    throw new Error("Provide a phoneNumber.");
  }

  const normalized = trimmed.replace(PHONE_SCHEME_PREFIX, "").trim();
  if (!normalized) {
    throw new Error("Provide a phoneNumber.");
  }

  return normalized;
}

export function normalizeEmailLookupInput(emailAddress: string): string {
  const trimmed = emailAddress.trim();
  if (!trimmed) {
    throw new Error("Provide an emailAddress.");
  }

  const normalized = trimmed.replace(EMAIL_SCHEME_PREFIX, "").trim().toLowerCase();
  if (!normalized) {
    throw new Error("Provide an emailAddress.");
  }

  return normalized;
}

export function normalizeContactIdentifier(contactIdentifier: string): string {
  const normalized = contactIdentifier.trim();
  if (!normalized) {
    throw new Error("Provide a contactIdentifier.");
  }

  return normalized;
}
