#!/bin/sh

sh -c '
  trap "" TERM
  printf "CHILD %s\n" "$$"
  while :; do
    sleep 1
  done
' &

sleep 0.2
exit 0
