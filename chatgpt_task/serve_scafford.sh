cd scaffold
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

npx @modelcontextprotocol/inspector python -m app.mcp_server