# Generate merkle proof  
From the root directory, run
```shell
$ node scripts/generateMerkleRoot.js -f example.json 
```

# Example.json
- The tokens can be of different lengths for each user.
- Consistency need not be maintained for each cycle. For instance, the token list can be of a different order.
- The amounts in `cumulativeAmounts` can be either strings, or hexadecimal string equivalents of their numerical values. Refer to the example.
