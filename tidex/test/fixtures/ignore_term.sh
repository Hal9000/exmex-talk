#!/bin/sh

trap '' TERM
printf 'READY %s\n' "$$"

while :; do
  sleep 1
done
