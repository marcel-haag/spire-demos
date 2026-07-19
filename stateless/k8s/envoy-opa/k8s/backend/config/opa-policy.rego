package envoy.authz

import rego.v1

http_request := input.attributes.request.http

default allow := false

# allow Frontend service to access Backend service
allow if {
    valid_path
    http_request.method == "GET"
    svc_spiffe_id == "spiffe://example.org/ns/default/sa/default/frontend"
}

# allow Frontend-2 service to access Backend service
allow if {
    valid_path
    http_request.method == "GET"
    svc_spiffe_id == "spiffe://example.org/ns/default/sa/default/frontend-2"
}

svc_spiffe_id := spiffe_id if {
    [_, _, uri_type_san] := split(http_request.headers["x-forwarded-client-cert"], ";")
    [_, spiffe_id] := split(uri_type_san, "=")
}

valid_path if {
    glob.match("/balances/*", [], http_request.path)
}

valid_path if {
    glob.match("/profiles/*", [], http_request.path)
}

valid_path if {
    glob.match("/transactions/*", [], http_request.path)
}