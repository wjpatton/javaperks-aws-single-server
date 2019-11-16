#!/bin/bash

# Create cust-connect job file
sudo bash -c "cat >/root/jobs/cust-connect-job.nomad" <<EOF
{
    "Job": {
        "ID": "cust-connect-job",
        "Name": "cust-connect",
        "Type": "service",
        "Datacenters": ["$REGION"],
        "TaskGroups": [{
            "Name": "cust-connect-group",
            "Tasks": [{
                "Name": "customer-api",
                "Driver": "java",
                "Count": 1,
                "Update": {
                    "Stagger": 10000000000,
                    "MaxParallel": 1,
                    "HealthCheck": "checks",
                    "MinHealthyTime": 10000000000,
                    "HealthyDeadline": 300000000000
                },
                "Vault": {
                    "Policies": ["access-creds"]
                },
                "Config": {
                    "jar_path": "local/javaperks-customer-api-0.2.6.jar",
                    "args": [ "server", "local/config.yml" ]
                },
                "Artifacts": [{
                    "GetterSource": "https://jubican-public.s3-us-west-2.amazonaws.com/jars/javaperks-customer-api-0.2.6.jar",
                    "RelativeDest": "local/"
                }],
                "Templates": [{
                    "EmbeddedTmpl": "logging:\n  level: INFO\n  loggers:\n    com.javaperks.api: DEBUG\nserver:\n  applicationConnectors:\n  - type: http\n    port: 5822\n    bindHost: 127.0.0.1\n  adminConnectors:\n  - type: http\n    port: 9001\nvaultAddress: \"http://vault-main.service.$REGION.consul:8200\"\nvaultToken: \"$VAULT_TOKEN\"\n",
                    "DestPath": "local/config.yml"
                }],
                "Resources": {
                    "CPU": 100,
                    "MemoryMB": 256,
                    "Networks": [{
                        "MBits": 1,
                        "ReservedPorts": [
                            {
                                "Label": "http",
                                "Value": 5822
                            }
                        ]
                    }]
                },
                "Services": [{
                    "Name": "customer-api",
                    "PortLabel": "http"
                }]
            }, {
                "Name": "consul-connect",
                "Driver": "raw_exec",
                "Count": 1,
                "Update": {
                    "Stagger": 10000000000,
                    "MaxParallel": 1,
                    "HealthCheck": "checks",
                    "MinHealthyTime": 10000000000,
                    "HealthyDeadline": 300000000000
                },
                "Config": {
                    "command": "/usr/local/bin/consul",
                    "args": [ 
                        "connect", "proxy",
                        "-service", "cust-db",
                        "-service-addr", "$CLIENT_IP",
                        "-listen", ":5822",
                        "-register" 
                    ]
                },
                "Resources": {
                    "CPU": 100,
                    "MemoryMB": 64,
                    "Networks": [{
                        "MBits": 1,
                        "ReservedPorts": [
                            {
                                "Label": "http",
                                "Value": 5822
                            }
                        ]
                    }]
                },
                "Services": [{
                    "Name": "cust-connect",
                    "PortLabel": "http"
                }]
            }]
        }]
    }
}
EOF

# Submit cust-connect job
# curl \
#     --request POST \
#     --data @/root/jobs/cust-connect-job.nomad \
#     http://nomad-server.service.us-east-1.consul:4646/v1/jobs

sudo bash -c "cat >/root/jobs/new-cust-connect-job.nomad" <<EOF
job "cust-connect-job" {
    datacenters = ["$REGION"]

    type = "service"
    update {
        stagger = "10s"
        max_parallel = 1
        health_check = "checks"
        min_healthy_time = "10s"
        healthy_deadline = "30s"
    }
    group "cust-connect-group" {
        count = 1
        network {
            mode = "bridge"
        }
        service {
            name = "customer-api"
            port = "http"

            connect {
                sidecar_service {
                    proxy {
                        upstreams {
                            destination_name = "customer-db"
                            local_bind_port  = 3306
                        }
                    }
                }
            }
        }
        task "customer-api" {
            driver = "java"
            vault {
                policies = ["access-creds"]
            }
            config {
                jar_path = "local/javaperks-customer-api-0.2.6.jar"
                args = ["server", "local/config.yml"]
            }
            artifact {
                source = "https://jubican-public.s3-us-west-2.amazonaws.com/jars/javaperks-customer-api-0.2.6.jar",
                destination = "local/"
            }
            template {
                data = "logging:\n  level: INFO\n  loggers:\n    com.javaperks.api: DEBUG\nserver:\n  applicationConnectors:\n  - type: http\n    port: 5822\n    bindHost: 127.0.0.1\n  adminConnectors:\n  - type: http\n    port: 9001\nvaultAddress: \"http://vault-main.service.$REGION.consul:8200\"\nvaultToken: \"$VAULT_TOKEN\"\n",
                destination = "local/config.yml"
            }
            resources {
                cpu = 100
                memory = 256
                network {
                    mbits = 1
                    port "http" {
                        static = 5822
                    }
                }
            }
        }
    }
}
EOF
