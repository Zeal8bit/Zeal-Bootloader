#!/bin/bash

usage() {
    echo "usage: $0 output_file address_1 file_1 ... address_n file_n" >&2
    exit 1
}

# Check if the number of arguments is odd
if [ $# -lt 3 ] || [ $(($# % 2)) -ne 1 ]; then
    usage
fi

# Create the output file
output_file="$1"
touch "$output_file"
shift

# Loop through the arguments in pairs: (address, file)
while (( "$#" )); do
    addr="$1"
    file="$2"
    printf "0x%04x - %s\n" "$addr" "$file"
    dd if="$file" of="$output_file" bs=1 seek="$(($addr))" status="none"
    shift 2
done
