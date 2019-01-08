#!/bin/sh

PATH="../../.build/release/:${PATH}"

rm -f geo.db
echo 'Loading...'
kineo-cli geo.db load geo.ttl

echo 'Querying...'
kineo-cli geo.db query coords.rq
rm -f geo.db
