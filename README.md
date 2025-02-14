# Kong Solace Plugin

## Overview

The **Kong Solace Plugin** allows Kong to push messages to a **Solace PubSub+ Event Broker** using either a **Topic** or **Queue**. This plugin enables seamless integration between Kong and Solace, facilitating message-driven architectures.

## Features

- Supports **Basic Authentication** and **OAuth2 Authentication** for secure communication with Solace.
- Allows dynamic configuration of Solace session properties.
- Supports both **direct** and **guaranteed** (persistent/non-persistent) messaging.
- Enables **custom content payloads** or direct payload forwarding.
- Configurable **acknowledgment wait time** to handle guaranteed message delivery.

## Installation

To install this plugin in Kong:

```shell
# Create an image of Kong with the Solace SDK
docker build --platform=linux/amd64 -t kong-with-solace:1.0 . 

# Update Kong configuration
export KONG_PLUGINS=bundled,solace

# Launch Kong
docker-compose up -d
```

## Configuration

To enable the plugin on a specific **Service** or **Route**, make the following request:

```shell
curl -X POST http://localhost:8001/services/{service}/plugins \
  --data "name=solace" \
  --data "config.session_host=http://solace-broker:55555" \
  --data "config.session_authentication_scheme=AUTHENTICATION_SCHEME_BASIC" \
  --data "config.session_username=admin" \
  --data "config.session_password=admin" \
  --data "config.message_destination_type=TOPIC" \
  --data "config.message_destination_name=my/topic" \
  --data "config.message_delivery_mode=DIRECT"
```

## Configuration Parameters

| Parameter                       | Type    | Default                       | Required | Description                                                                                    |
| ------------------------------- | ------- | ----------------------------- | -------- | ---------------------------------------------------------------------------------------------- |
| `session_host`                  | URL     | -                             | ✅        | The Solace broker host.                                                                        |
| `session_authentication_scheme` | String  | `AUTHENTICATION_SCHEME_BASIC` | ✅        | Authentication scheme (`NONE`, `AUTHENTICATION_SCHEME_BASIC`, `AUTHENTICATION_SCHEME_OAUTH2`). |
| `session_username`              | String  | -                             | ❌        | Username for Basic Authentication.                                                             |
| `session_password`              | String  | -                             | ❌        | Password for Basic Authentication.                                                             |
| `session_oauth2_access_token`   | String  | -                             | ❌        | OAuth2 access token (if using OAuth2 authentication).                                          |
| `session_oidc_id_token`         | String  | -                             | ❌        | OIDC ID token (if using OAuth2 authentication).                                                |
| `session_vpn_name`              | String  | -                             | ❌        | VPN name for Solace session.                                                                   |
| `session_connect_timeout_ms`    | Integer | `3000`                        | ✅        | Connection timeout in milliseconds.                                                            |
| `session_write_timeout_ms`      | Integer | `3000`                        | ✅        | Write timeout in milliseconds.                                                                 |
| `solace_session_pool`           | Integer | `2`                           | ✅        | Number of sessions in the pool (0-10).                                                         |
| `message_delivery_mode`         | String  | `DIRECT`                      | ✅        | Delivery mode (`DIRECT`, `PERSISTENT`, `NONPERSISTENT`).                                       |
| `message_destination_type`      | String  | `TOPIC`                       | ✅        | Destination type (`TOPIC` or `QUEUE`).                                                         |
| `message_destination_name`      | String  | `tutorial/topic`              | ✅        | Topic or queue name where messages will be sent.                                               |
| `message_content_type`          | String  | `PAYLOAD`                     | ✅        | Message content type (`PAYLOAD`, `CUSTOM`).                                                    |
| `message_content_override`      | String  | `Hello World!`                | ❌        | Custom message content (if `CUSTOM` is selected).                                              |
| `ack_max_wait_time_ms`          | Integer | `2000`                        | ✅        | Maximum wait time for acknowledgment (ms).                                                     |
| `solace_sdk_log_level`          | Integer | `0`                           | ✅        | Logging level (0-7).                                                                           |
| `kong/plugins/solace/schema.lua`| Array   | -                             | ✅        | Solace Sessions confiuration, each property has a name and a value.                                                    |

## Example Request

Once the plugin is enabled, sending a request to the configured Kong route will push a message to Solace:

```shell
curl -X POST http://localhost:8000/send-message \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello from Kong!"}'
```

If configured correctly, the message will be sent to Solace and processed accordingly.

## License

This project is licensed under the **MIT License**.

---

For more details, refer to the official **Solace PubSub+ API Documentation** or visit [KongHQ](https://konghq.com/).

