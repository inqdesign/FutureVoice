import json, subprocess, base64, sys, urllib.request

def token():
    raw = subprocess.run(["security","find-generic-password","-s","Supabase CLI","-w"],
                         capture_output=True, text=True, check=True).stdout.strip()
    if raw.startswith("go-keyring-base64:"):
        raw = base64.b64decode(raw[len("go-keyring-base64:"):]).decode()
    return raw

REF = "chhzjtigzdotacutwcyo"

def run(sql):
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{REF}/database/query",
        data=json.dumps({"query": sql}).encode(),
        headers={"Authorization": f"Bearer {token()}",
                 "Content-Type": "application/json",
                 "User-Agent": "futurevoice-admin/1.0"},
        method="POST")
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return {"__error__": e.read().decode(), "__status__": e.code}

if __name__ == "__main__":
    sql = sys.stdin.read() if sys.argv[1:] == ["-"] else " ".join(sys.argv[1:])
    print(json.dumps(run(sql), indent=2, default=str)[:8000])
