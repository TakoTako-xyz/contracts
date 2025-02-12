// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import '../interfaces/IPriceFeed.sol';
import '../dependencies/openzeppelin/contracts/SafeMath.sol';

interface IApi3Proxy {
  function read() external view returns (int224 value, uint32 timestamp);
}

/*
 * The Api3PriceFeed uses Api3 as primary oracle.
 */
contract Api3PriceFeed is IPriceFeed {
  using SafeMath for uint256;

  uint256 public constant DECIMAL_PRECISION = 1e18;

  IApi3Proxy public oracle;

  // Use to convert a price answer to an 18-digit precision uint
  uint256 public constant TARGET_DIGITS = 18;

  // Maximum time period allowed since Api3's latest round data timestamp, beyond which Api3 is considered frozen.
  // For stablecoins we recommend 90000, as Api3 updates once per day when there is no significant price movement
  // For volatile assets we recommend 14400 (4 hours)
  uint256 public immutable TIMEOUT;

  // Maximum deviation allowed between two consecutive Api3 oracle prices. 18-digit precision.
  uint256 public constant MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND = 5e17; // 50%

  /*
   * The maximum relative price difference between two oracle responses allowed in order for the PriceFeed
   * to return to using the Api3 oracle. 18-digit precision.
   */
  uint256 public constant MAX_PRICE_DIFFERENCE_BETWEEN_ORACLES = 5e16; // 5%

  // The last good price seen from an oracle by Liquity
  uint256 public lastGoodPrice;

  struct OracleResponse {
    uint256 answer;
    uint256 timestamp;
    bool success;
  }

  enum Status {
    oracleWorking,
    oracleUntrusted
  }

  // The current status of the PricFeed, which determines the conditions for the next price fetch attempt
  Status public status;

  event LastGoodPriceUpdated(uint256 _lastGoodPrice);
  event PriceFeedStatusChanged(Status newStatus);

  // --- Dependency setters ---

  constructor(IApi3Proxy _oracle, uint256 _timeout) {
    oracle = _oracle;
    TIMEOUT = _timeout;

    // Explicitly set initial system status
    status = Status.oracleWorking;

    // Get an initial price from Api3 to serve as first reference for lastGoodPrice
    OracleResponse memory response = _getCurrentResponse();

    require(
      !_oracleIsBroken(response) && block.timestamp.sub(response.timestamp) < _timeout,
      'PriceFeed: Api3 must be working and current'
    );

    lastGoodPrice = response.answer;
  }

  // --- Functions ---

  /*
   * fetchPrice():
   * Returns the latest price obtained from the Oracle. Called by Liquity functions that require a current price.
   *
   * Also callable by anyone externally.
   *
   * Non-view function - it stores the last good price seen by Liquity.
   *
   * Uses a main oracle (Api3). If it fails,
   * it uses the last good price seen by Liquity.
   *
   */
  function fetchPrice() external view override returns (uint256) {
    (, uint256 price) = _fetchPrice();
    return price;
  }

  function updatePrice() external override returns (uint256) {
    (Status newStatus, uint256 price) = _fetchPrice();
    lastGoodPrice = price;
    if (status != newStatus) {
      status = newStatus;
      emit PriceFeedStatusChanged(newStatus);
    }
    return price;
  }

  function _fetchPrice() internal view returns (Status, uint256) {
    // Get current and previous price data from Api3, and current price data from Band
    OracleResponse memory response = _getCurrentResponse();

    // --- CASE 1: System fetched last price from Api3  ---
    if (status == Status.oracleWorking) {
      // If Api3 is broken or frozen
      if (_oracleIsBroken(response) || _oracleIsFrozen(response)) {
        // If Api3 is broken, switch to Band and return current Band price
        return (Status.oracleUntrusted, lastGoodPrice);
      }

      // If Api3 is working, return Api3 current price (no status change)
      return (Status.oracleWorking, response.answer);
    }

    // --- CASE 2: Api3 oracle is untrusted at the last price fetch ---
    if (status == Status.oracleUntrusted) {
      if (_oracleIsBroken(response) || _oracleIsFrozen(response)) {
        return (Status.oracleUntrusted, lastGoodPrice);
      }

      return (Status.oracleWorking, response.answer);
    }
  }

  // --- Helper functions ---

  /* Api3 is considered broken if its current or previous round data is in any way bad. We check the previous round
   * for two reasons:
   *
   * 1) It is necessary data for the price deviation check in case 1,
   * and
   * 2) Api3 is the PriceFeed's preferred primary oracle - having two consecutive valid round responses adds
   * peace of mind when using or returning to Api3.
   */
  function _oracleIsBroken(OracleResponse memory _response) internal view returns (bool) {
    // Check for response call reverted
    if (!_response.success) {
      return true;
    }
    // Check for an invalid timeStamp that is 0, or in the future
    if (_response.timestamp == 0 || _response.timestamp > block.timestamp) {
      return true;
    }
    // Check for non-positive price (original value returned from Api3 is int256)
    if (int256(_response.answer) <= 0) {
      return true;
    }

    return false;
  }

  function _oracleIsFrozen(OracleResponse memory _response) internal view returns (bool) {
    return block.timestamp.sub(_response.timestamp) > TIMEOUT;
  }

  function _scalePriceByDigits(uint256 _price, uint32 _digits) internal pure returns (uint256) {
    /*
     * Convert the price returned by the Api3 oracle to an 18-digit decimal for use by Liquity.
     * At date of Liquity launch, Api3 uses an 8-digit price, but we also handle the possibility of
     * future changes.
     */
    uint256 price;
    if (_digits >= TARGET_DIGITS) {
      // Scale the returned price value down to Liquity's target precision
      price = _price.div(10 ** (_digits - TARGET_DIGITS));
    } else if (_digits < TARGET_DIGITS) {
      // Scale the returned price value up to Liquity's target precision
      price = _price.mul(10 ** (TARGET_DIGITS - _digits));
    }
    return price;
  }

  // --- Oracle response wrapper functions ---

  function _getCurrentResponse() internal view returns (OracleResponse memory response) {
    // Try to get latest price data:
    try oracle.read() returns (int224 value, uint32 timestamp) {
      // If call to Api3 succeeds, return the response and success = true
      response.answer = uint256(value);
      response.timestamp = timestamp;
      response.success = true;
      return response;
    } catch {
      // If call to Api3 aggregator reverts, return a zero response with success = false
      return response;
    }
  }
}
