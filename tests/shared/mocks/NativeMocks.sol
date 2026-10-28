// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IPaymentRails } from "../../../src/interfaces/IPaymentRails.sol";

/// @dev Sends native value via transfer/send (2300-gas stipend) or call (all gas).
contract StipendSender {
    function sendWithTransfer(address payable to, uint256 amount) external {
        to.transfer(amount);
    }

    function sendWithSend(address payable to, uint256 amount) external returns (bool ok) {
        ok = to.send(amount);
    }

    function sendWithCall(address payable to, uint256 amount) external returns (bool ok) {
        (ok,) = to.call{ value: amount }("");
    }

    receive() external payable { }
}

/// @dev WETH9 look-alike whose deposit() re-enters wrapNative() on the caller; records the selector the nested
///      call was rejected with (zero if it went through).
contract ReentrantWETH9 is ERC20 {
    bytes4 public rejectedWith;

    constructor() ERC20("Reentrant Wrapped", "RWRAP") { }

    function deposit() external payable {
        try IPaymentRails(msg.sender).wrapNative() {
            rejectedWith = bytes4(0);
        } catch (bytes memory reason) {
            rejectedWith = bytes4(reason);
        }
        _mint(msg.sender, msg.value);
    }
}

/// @dev Mis-set wrapper: credits only half of a deposit and pays out only half of a withdrawal.
contract ShortMintWETH9 is ERC20 {
    constructor() ERC20("Short Wrapped", "SWRAP") { }

    function deposit() external payable {
        _mint(msg.sender, msg.value / 2);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        (bool ok,) = msg.sender.call{ value: amount / 2 }("");
        require(ok, "ShortMintWETH9: payout failed");
    }

    receive() external payable { }
}

/// @dev Recipient whose receive() always reverts.
contract RejectingRecipient {
    receive() external payable {
        revert("RejectingRecipient: refused");
    }
}

/// @dev Recipient whose receive() re-enters wrapNative() on the caller during a sweep; records the selector the
///      nested call was rejected with (zero if it went through).
contract ReentrantSweepRecipient {
    bytes4 public rejectedWith;

    receive() external payable {
        try IPaymentRails(msg.sender).wrapNative() {
            rejectedWith = bytes4(0);
        } catch (bytes memory reason) {
            rejectedWith = bytes4(reason);
        }
    }
}
