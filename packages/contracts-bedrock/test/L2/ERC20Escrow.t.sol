// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing utilities
import { CommonTest } from "test/setup/CommonTest.sol";

// Error imports
import { Unauthorized, NotCustomGasToken } from "src/libraries/errors/CommonErrors.sol";

// Target contract
import { ERC20Escrow } from "src/L2/ERC20Escrow.sol";

// Token contract
import { Token } from "../ERC20.t.sol";

/// @title ERC20Escrow_Test
/// @notice Contract for testing the ERC20Escrow contract.
contract ERC20Escrow_Test is CommonTest {
    ERC20Escrow public escrow;
    Token public token;

    function setUp() public override {
        // Initialize the target contract
        escrow = new ERC20Escrow();
        token = new Token("TOKEN", "TKN");
        token.mint(address(this), 100);
    }

    address _sender = address(this);
    address _receiver = address(0x123);
    address _token = address(token);
    uint _lockPeriod = 1;
    uint _amount = uint(1);

    function testERC20Escrow() external {
        // lock token
        vm.prank(address(this));
        token.approve(address(escrow), _amount);
        escrow.lockToken(_lockPeriod, _receiver, _token, _amount);

        // fast forward block
        skip(3600);
        uint _lockIdx = escrow.currentIdx() - 1;

        // unlock token
        vm.prank(_sender);
        escrow.unlockToken(_receiver, _lockIdx);

        // withdraw token
        vm.prank(_receiver);
        escrow.withdrawToken(_sender, _receiver, _lockIdx);
    }
}
