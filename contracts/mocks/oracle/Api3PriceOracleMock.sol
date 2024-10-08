// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.6;

interface IApi3Proxy {
  function read() external view returns (int224 value, uint32 timestamp);
}

contract Api3PriceOracleMock is IApi3Proxy {
  int224 public value;
  uint32 public timestamp;

  function setPrice(int224 _value, uint32 _timestamp) external {
    value = _value;
    timestamp = _timestamp;
  }

  function read() external view override returns (int224, uint32) {
    return (value, timestamp);
  }
}
