# Generate merkle proof  
From the root directory run
```shell
$ $ node scripts/generateMerkleRoot.js -f example.json 
{
  "cycle": 3,
  "merkleRoot": "0x8d831c4287c6ccb89aebf21dfe45314359711a4f713da541b57d09562d9bca91",
  "userRewards": {
    "0xD4cF9b9bDe051e1162fea423Ac4C444B83a2d301": {
      "index": 0,
      "tokens": [
        "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"
      ],
      "cumulativeAmounts": [
        "0x2710"
      ],
      "proof": [
        "0x97e6893721398bbf5811dbc62b7ef47bc4c49f64555a459210184bb1d36088fa"
      ]
    },
    "0x91F4d9EA5c1ee0fc778524b3D57fD8CF700996Cf": {
      "index": 1,
      "tokens": [
        "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"
      ],
      "cumulativeAmounts": [
        "0x2710"
      ],
      "proof": [
        "0xe1d227fef4618cd6f6c3edb35fe834def4e6bf6758efad9c6ac677bc0816caee"
      ]
    }
  }
}
```