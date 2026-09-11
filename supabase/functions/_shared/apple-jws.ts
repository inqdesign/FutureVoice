// Apple JWS verification, shared by apple-webhook (server notifications) and
// apple-claim (a transaction the APP hands us from StoreKit). Both carry the
// same envelope — ES256 over `header.body`, an x5c chain in the header — and
// both must be checked the same four ways, in order: read the chain, verify
// each link against the next one's key, require the last to be byte-identical
// to a pinned Apple root, then verify the body with the leaf's key. Step 2 is
// not optional: Apple's root is public, so pinning alone would let anyone
// append it to their own leaf.
//
// Apple's official library cannot run here — its chain check goes through
// node:crypto's X509Certificate.verify(), which the Supabase edge runtime does
// not implement (see apple-webhook's header). @peculiar/x509 on Web Crypto is
// the replacement, verified end-to-end on 2026-08-20.

import { Buffer } from "node:buffer"
import * as x509 from "npm:@peculiar/x509@1.12.3"

// Apple's public root CAs, pinned (downloaded from
// https://www.apple.com/certificateauthority/ — G3 signs current App Store
// receipts; G2 kept for completeness).
const APPLE_ROOT_CA_G3_B64 =
  "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA=="
const APPLE_ROOT_CA_G2_B64 =
  "MIIFkjCCA3qgAwIBAgIIAeDltYNno+AwDQYJKoZIhvcNAQEMBQAwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEcyMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxMDA5WhcNMzkwNDMwMTgxMDA5WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzIxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANgREkhI2imKScUcx+xuM23+TfvgHN6sXuI2pyT5f1BrTM65MFQn5bPW7SXmMLYFN14UIhHF6Kob0vuy0gmVOKTvKkmMXT5xZgM4+xb1hYjkWpIMBDLyyED7Ul+f9sDx47pFoFDVEovy3d6RhiPw9bZyLgHaC/YuOQhfGaFjQQscp5TBhsRTL3b2CtcM0YM/GlMZ81fVJ3/8E7j4ko380yhDPLVoACVdJ2LT3VXdRCCQgzWTxb+4Gftr49wIQuavbfqeQMpOhYV4SbHXw8EwOTKrfl+q04tvny0aIWhwZ7Oj8ZhBbZF8+NfbqOdfIRqMM78xdLe40fTgIvS/cjTf94FNcX1RoeKz8NMoFnNvzcytN31O661A4T+B/fc9Cj6i8b0xlilZ3MIZgIxbdMYs0xBTJh0UT8TUgWY8h2czJxQI6bR3hDRSj4n4aJgXv8O7qhOTH11UL6jHfPsNFL4VPSQ08prcdUFmIrQB1guvkJ4M6mL4m1k8COKWNORj3rw31OsMiANDC1CvoDTdUE0V+1ok2Az6DGOeHwOx4e7hqkP0ZmUoNwIx7wHHHtHMn23KVDpA287PT0aLSmWaasZobNfMmRtHsHLDd4/E92GcdB/O/WuhwpyUgquUoue9G7q5cDmVF8Up8zlYNPXEpMZ7YLlmQ1A/bmH8DvmGqmAMQ0uVAgMBAAGjQjBAMB0GA1UdDgQWBBTEmRNsGAPCe8CjoA1/coB6HHcmjTAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBBjANBgkqhkiG9w0BAQwFAAOCAgEAUabz4vS4PZO/Lc4Pu1vhVRROTtHlznldgX/+tvCHM/jvlOV+3Gp5pxy+8JS3ptEwnMgNCnWefZKVfhidfsJxaXwU6s+DDuQUQp50DhDNqxq6EWGBeNjxtUVAeKuowM77fWM3aPbn+6/Gw0vsHzYmE1SGlHKy6gLti23kDKaQwFd1z4xCfVzmMX3zybKSaUYOiPjjLUKyOKimGY3xn83uamW8GrAlvacp/fQ+onVJv57byfenHmOZ4VxG/5IFjPoeIPmGlFYl5bRXOJ3riGQUIUkhOb9iZqmxospvPyFgxYnURTbImHy99v6ZSYA7LNKmp4gDBDEZt7Y6YUX6yfIjyGNzv1aJMbDZfGKnexWoiIqrOEDCzBL/FePwN983csvMmOa/orz6JopxVtfnJBtIRD6e/J/JzBrsQzwBvDR4yGn1xuZW7AYJNpDrFEobXsmII9oDMJELuDY++ee1KG++P+w8j2Ud5cAeh6Squpj9kuNsJnfdBrRkBof0Tta6SqoWqPQFZ2aWuuJVecMsXUmPgEkrihLHdoBR37q9ZV0+N0djMenl9MU/S60EinpxLK8JQzcPqOMyT/RFtm2XNuyE9QoB6he7hY1Ck3DDUOUUi78/w0EP3SIEIwiKum1xRKtzCTrJ+VKACd+66eYWyi4uTLLT3OUEVLLUNIAytbwPF+E="

const ROOT_CAS = [
  Buffer.from(APPLE_ROOT_CA_G3_B64, "base64"),
  Buffer.from(APPLE_ROOT_CA_G2_B64, "base64"),
]

/** Verify an Apple-signed JWS and return its payload. Throws on any defect. */
export async function verifyAppleJWS(jws: string): Promise<Record<string, any>> {
  const [rawHeader, rawBody, rawSig] = jws.split(".")
  if (!rawHeader || !rawBody || !rawSig) throw new Error("malformed JWS")

  const header = JSON.parse(b64url(rawHeader).toString("utf8"))
  if (header.alg !== "ES256") throw new Error(`unexpected alg ${header.alg}`)
  const chain: string[] = header.x5c ?? []
  if (chain.length < 2) throw new Error(`x5c too short (${chain.length})`)

  const certs = chain.map((c) => new x509.X509Certificate(Buffer.from(c, "base64")))

  // The pinned end of the chain. Byte equality rather than "the issuer name
  // looks right": a forged chain can restate any name it likes, and this is
  // the one link an attacker cannot.
  const rootDer = new Uint8Array(certs[certs.length - 1].rawData)
  if (!ROOT_CAS.some((pinned) => equalBytes(new Uint8Array(pinned), rootDer))) {
    throw new Error("chain does not end at a pinned Apple root")
  }

  // Every link verified against the next one's key. Without this, the check
  // above would let anyone append Apple's (public) root to their own leaf.
  const now = new Date()
  for (let i = 0; i < certs.length; i++) {
    const cert = certs[i]
    if (now < cert.notBefore || now > cert.notAfter) {
      throw new Error(`cert ${i} outside its validity window`)
    }
    if (i + 1 < certs.length) {
      const ok = await cert.verify({ publicKey: certs[i + 1].publicKey, signatureOnly: true })
      if (!ok) throw new Error(`cert ${i} not signed by cert ${i + 1}`)
    }
  }

  const key = await certs[0].publicKey.export()
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    b64url(rawSig),
    new TextEncoder().encode(`${rawHeader}.${rawBody}`),
  )
  if (!ok) throw new Error("JWS signature does not match the leaf certificate")

  return JSON.parse(b64url(rawBody).toString("utf8"))
}

/** JWS payload claims WITHOUT signature checking — diagnostics only. */
export function peekJWSUnverified(jws: string): Record<string, any> | null {
  try {
    const [, body] = jws.split(".")
    return JSON.parse(b64url(body).toString("utf8"))
  } catch {
    return null
  }
}

export function b64url(s: string): Buffer {
  return Buffer.from(s.replace(/-/g, "+").replace(/_/g, "/"), "base64")
}

function equalBytes(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false
  return true
}

/** Epoch milliseconds → ISO string, the shape both tables store. */
export function isoFromMs(epochMs: number): string {
  return new Date(epochMs).toISOString()
}
