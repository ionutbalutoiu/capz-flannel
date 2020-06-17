#!/usr/bin/env python3

import datetime
import json
import sys


def log(message):
    print("{:%Y-%m-%d %H:%M:%S} - {}".format(datetime.datetime.now(), message))

json_input = json.load(sys.stdin)
all_ready = True

for machine in json_input['items']:
    if 'status' not in machine:
        all_ready = False
        continue

    if machine['status']['phase'] == 'Running':
        continue

    all_ready = False
    log("Machine %s is not Running. Current status: %s" % (
        machine['metadata']['name'],
        machine['status']['phase']))

if not all_ready:
    sys.exit(1)

sys.exit(0)
