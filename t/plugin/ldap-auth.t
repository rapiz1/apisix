#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
use t::APISIX 'no_plan';

repeat_each(2);
no_long_string();
no_root_location();
no_shuffle();
add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();


__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.ldap-auth")
            local ok, err = plugin.check_schema({user_dn = 'foo'}, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: wrong type of string
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ldap-auth")
            local ok, err = plugin.check_schema({base_dn = 123, ldap_uri = "127.0.0.1:1389"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body_like eval
qr/wrong type: expected string, got number
done
/



=== TEST 3: add consumer with username and plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "user01",
                    "plugins": {
                        "ldap-auth": {
                            "user_dn": "cn=user01,ou=users,dc=example,dc=org"
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "user01",
                            "plugins": {
                                "ldap-auth": {
                                    "user_dn": "cn=user01,ou=users,dc=example,dc=org"
                                }
                            }
                        }
                    },
                    "action": "set"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: enable basic auth plugin using admin api
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ldap-auth": {
                            "base_dn": "ou=users,dc=example,dc=org",
                            "ldap_uri": "127.0.0.1:1389",
                            "uid": "cn"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 5: verify, missing authorization
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing authorization in request"}



=== TEST 6: verify, invalid password
--- request
GET /hello
--- more_headers
Authorization: Basic Zm9vOmZvbwo=
--- error_code: 401
--- response_body
{"message":"Invalid user authorization"}



=== TEST 7: verify
--- request
GET /hello
--- more_headers
Authorization: Basic dXNlcjAxOnBhc3N3b3JkMQ==
--- response_body
hello world
--- error_log
find consumer user01



=== TEST 8: enable basic auth plugin using admin api
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ldap-auth": {
                            "base_dn": "ou=users,dc=example,dc=org",
                            "ldap_uri": "127.0.0.1:1389",
                            "uid": "cn"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 9: verify
--- request
GET /hello
--- more_headers
Authorization: Basic dXNlcjAxOnBhc3N3b3JkMQ==
--- response_body
hello world
--- error_log
find consumer user01



=== TEST 10: invalid schema
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            for _, case in ipairs({
                {},
                "blah"
            }) do
                local code, body = t('/apisix/admin/consumers',
                    ngx.HTTP_PUT,
                    {
                        username = "foo",
                        plugins = {
                            ["ldap-auth"] = case
                        }
                    }
                )
                ngx.print(body)
            end
        }
    }
--- response_body
{"error_msg":"invalid plugins configuration: failed to check the configuration of plugin ldap-auth err: property \"user_dn\" is required"}
{"error_msg":"invalid plugins configuration: invalid plugin conf \"blah\" for plugin [ldap-auth]"}



=== TEST 11: get the default schema
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/schema/plugins/ldap-auth',
                ngx.HTTP_GET,
                nil,
                [[
{"title":"work with route or service object","required":["base_dn","ldap_uri"],"properties":{"base_dn":{"type":"string"},"ldap_uri":{"type":"string"},"use_tls":{"type":"boolean"},"disable":{"type":"boolean"},"uid":{"type":"string"}},"type":"object"}
                ]]
                )
            ngx.status = code
        }
    }



=== TEST 12: get the schema by schema_type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/schema/plugins/ldap-auth?schema_type=consumer',
                ngx.HTTP_GET,
                nil,
                [[
{"title":"work with consumer object","required":["user_dn"],"properties":{"user_dn":{"type":"string"}},"type":"object"}
                ]]
                )
            ngx.status = code
        }
    }



=== TEST 13: get the schema by error schema_type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/schema/plugins/ldap-auth?schema_type=consumer123123',
                ngx.HTTP_GET,
                nil,
                [[
{"title":"work with route or service object","required":["base_dn","ldap_uri"],"properties":{"base_dn":{"type":"string"},"ldap_uri":{"type":"string"},"use_tls":{"type":"boolean"},"disable":{"type":"boolean"},"uid":{"type":"string"}},"type":"object"}                ]]
                )
            ngx.status = code
        }
    }