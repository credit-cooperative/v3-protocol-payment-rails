// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

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

/// @dev Recipient whose receive() always reverts.
contract RejectingRecipient {
    receive() external payable {
        revert("RejectingRecipient: refused");
    }
}

/// @dev Recipient whose receive() re-enters sweepNative() on the caller during a sweep; records the selector the
///      nested call was rejected with (zero if it went through).
contract ReentrantSweepRecipient {
    bytes4 public rejectedWith;

    receive() external payable {
        try IPaymentRails(msg.sender).sweepNative(address(this)) {
            rejectedWith = bytes4(0);
        } catch (bytes memory reason) {
            rejectedWith = bytes4(reason);
        }
    }
}
