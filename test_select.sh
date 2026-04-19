#!/bin/bash
options=("user1 (Personal)" "orgA" "orgB")
org_list=("orgA" "orgB")
# Simulating what we do
# User chooses 2
echo "Select choice:"
# We don't want it to actually wait if it's run via run_command, we can pipe input to it.
