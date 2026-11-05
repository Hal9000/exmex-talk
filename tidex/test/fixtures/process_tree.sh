#!/bin/sh

sleep 300 &
child=$!
printf 'CHILD %s\n' "$child"
wait "$child"
