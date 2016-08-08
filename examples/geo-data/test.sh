#!/bin/sh

rm -f geo.db
echo 'Loading...'
kineo-cli geo.db load geo.nt

echo 'Querying...'
kineo-cli geo.db query coords.q
