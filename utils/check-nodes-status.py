#!/usr/bin/env python3

import datetime
import json
import sys


def log(message):
    print("{:%Y-%m-%d %H:%M:%S} - {}".format(datetime.datetime.now(), message))

json_input = json.load(sys.stdin)
all_ready = True

for node in json_input['items']:
    if 'status' not in node:
        all_ready = False
        continue

    ready_condition = [c for c in node['status']['conditions']
                       if c['type'] == 'Ready']
    if len(ready_condition) == 0 or ready_condition[0]['status'] == 'False':
        log("Node %s is not ready" % node['metadata']['name'])
        all_ready = False

if not all_ready:
    sys.exit(1)

sys.exit(0)
