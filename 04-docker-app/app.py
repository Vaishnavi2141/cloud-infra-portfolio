from flask import Flask
import datetime
import os

app = Flask(__name__)

@app.route("/")
def home():
    return f"""
    <html>
      <body>
        <h1>Cloud Infra Demo App</h1>
        <p>Server time: {datetime.datetime.now()}</p>
        <p>Hostname: {os.uname().nodename}</p>
      </body>
    </html>
    """

@app.route("/health")
def health():
    return {{"status": "ok", "time": str(datetime.datetime.now())}}

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)

