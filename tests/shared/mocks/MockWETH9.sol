// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev WETH9 stand-in: deposit() and plain value transfers mint 1:1; withdraw() burns and pays out with `transfer`,
///      i.e. the 2300-gas stipend, exactly like the canonical contract.
contract MockWETH9 is ERC20 {
    constructor() ERC20("Wrapped Native", "WNATIVE") { }

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }

    receive() external payable {
        _mint(msg.sender, msg.value);
    }
}
