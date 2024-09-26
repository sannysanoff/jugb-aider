#!/bin/bash

# Read the input and process it line by line
awk '
    # Initialize variables
    BEGIN { prev_plus = 0 }
    
    # Process each line
    {
        # If the line starts with "+"
        if ($0 ~ /^\+/) {
            # If the previous line didnt start with "+", print this line
            if (prev_plus == 0 && length($0) >= 15) {
                print $0
            }
            prev_plus = 1
        } else {
            prev_plus = 0
        }
    }
' "$1"
