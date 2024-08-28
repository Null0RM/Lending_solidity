// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPriceOracle {
    function getPrice(address token) external view returns (uint256);
    function setPrice(address token, uint256 price) external;
}

contract UpsideLending {
    IPriceOracle priceOraclce;
    address usdc;

    mapping(address => uint256) user_borrowed_usdc;
    mapping(address => uint256) deposit_ether;
    mapping(address => uint256) deposit_usdc;

    mapping(address => uint256) total_deposited;

    constructor(IPriceOracle _oracle, address _usdc) {
        priceOraclce = _oracle;
    }

    function initializeLendingProtocol(address _token) external payable {
        usdc = _token;
        IERC20(usdc).transferFrom(msg.sender, address(this), msg.value);
    }
    
    function deposit(address _token, uint256 _depositAmount) external payable {
        if (_token == address(0))
        {
            require(_depositAmount == msg.value, "ARG_AND_RECEIVED_ETHER_MISMATCH");
            deposit_ether[msg.sender] += _depositAmount;
            total_deposited[address(0)] += _depositAmount;
        }
        else
        {
            require(IERC20(usdc).balanceOf(msg.sender) >= _depositAmount, "INSUFFICIENT_ALLOWANCE");
            IERC20(usdc).transferFrom(msg.sender, address(this), _depositAmount);
            deposit_usdc[msg.sender] += _depositAmount;
            total_deposited[address(_token)] += _depositAmount;
        }
    }

    function borrow(address _token, uint256 _amount) external {
        require(total_deposited[address(_token)] >= _amount, "INSUFFICIENT_VAULT_BALANCE");
        
        uint ETH_PRICE = priceOraclce.getPrice(address(0));
        uint USDC_PRICE = priceOraclce.getPrice(address(usdc));
        uint TOKEN_PRICE = priceOraclce.getPrice(address(_token));
        
        uint user_collateral = ETH_PRICE * deposit_ether[msg.sender] + USDC_PRICE * deposit_usdc[msg.sender];
        uint user_borrow_price = TOKEN_PRICE * _amount;
        uint user_current_debt_price = USDC_PRICE * user_borrowed_usdc[msg.sender];
        require(user_collateral >= (user_borrow_price + user_current_debt_price) * 2, "INSUFFICIENT_COLLATERAL");
        
        user_borrowed_usdc[msg.sender] += _amount;
        total_deposited[address(usdc)] -= _amount;
        IERC20(_token).transfer(msg.sender, _amount);
    }

    function repay() external {}
    function withdraw(address _to, uint256 _amount) external {}
    function getAccruedSupplyAmount(address _token) external returns (uint256 accruedSupply) {}
    function liquidate() external {}
}
