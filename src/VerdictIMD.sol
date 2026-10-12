// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title VerdictIMD
/// @notice A fixed supply of one billion VERDICT, with 18 decimals, minted to the deployer.
/// @dev During a factory launch, msg.sender is the factory. There are no subsequent mint,
/// burn, administrative, or upgrade entry points, and transfers have no fees or restrictions
/// beyond the standard ERC-20 balance, allowance, and zero-address checks.
contract VerdictIMD is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("VerdictIMD", "VERDICT") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
