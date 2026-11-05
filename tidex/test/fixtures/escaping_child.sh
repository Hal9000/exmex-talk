#!/bin/sh

trap 'exit 0' TERM

sh -c '
  trap "" TERM
  printf "CHILD %s\n" "$$"
  while :; do
    sleep 1
  done
' &

while :; do
  sleep 1
done
