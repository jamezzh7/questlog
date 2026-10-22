"""JSON entry point for the bundled, in-process Mac App Store runtime."""
import json
from api_service import LocalAPI
from git_metadata import read_activity


def dispatch(request_json, config_path):
    request = json.loads(request_json)
    if not isinstance(request, dict):
        raise ValueError("请求格式不正确")
    # These grants come from the native access manager, never the web message.
    roots = request.get("authorizedRoots", [])
    registries = request.get("registries", {})
    if not isinstance(roots, list) or not all(isinstance(p, str) for p in roots) or not isinstance(registries, dict):
        raise ValueError("授权信息不正确")
    api = LocalAPI(config_path, authorized_roots=roots, registries=registries, activity_reader=read_activity)
    status, result = api.request(request.get("method", "GET"), request.get("path", ""), request.get("body"))
    return json.dumps({"status": status, "body": result}, ensure_ascii=False, allow_nan=False)
