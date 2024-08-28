// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPriceOracle {
    function getPrice(address token) external view returns (uint256);
    function setPrice(address token, uint256 price) external;
}

contract UpsideLending {
    event logging(uint, uint);
    
    IPriceOracle priceOraclce;
    address usdc;
    uint256 interest_rate;

    mapping(address => uint256) user_borrowed_usdc;
    mapping(address => uint256) deposit_ether;
    mapping(address => uint256) deposit_usdc;

    mapping(address => uint256) total_deposited;

    mapping(address => uint256) last_update;

    constructor(IPriceOracle _oracle, address _usdc) {
        priceOraclce = _oracle;
        interest_rate = 5;
        usdc = _usdc;
    }

    function initializeLendingProtocol(address _token) external payable {
        usdc = _token;
        IERC20(usdc).transferFrom(msg.sender, address(this), msg.value);
    }
    
    function deposit(address _token, uint256 _depositAmount) external payable {
        update(msg.sender);

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
        update(msg.sender);
        require(total_deposited[address(_token)] >= _amount, "INSUFFICIENT_VAULT_BALANCE");
        
        uint ETH_PRICE = priceOraclce.getPrice(address(0));
        uint USDC_PRICE = priceOraclce.getPrice(address(usdc));
        uint TOKEN_PRICE = priceOraclce.getPrice(address(_token));
        
        uint user_deposited_price = ETH_PRICE * deposit_ether[msg.sender] + USDC_PRICE * deposit_usdc[msg.sender];
        uint user_borrow_price = TOKEN_PRICE * _amount;
        uint user_current_debt_price = USDC_PRICE * user_borrowed_usdc[msg.sender];
        emit logging(user_borrow_price, user_borrowed_usdc[msg.sender]);
        require(user_deposited_price >= (user_borrow_price + user_current_debt_price) * 2, "INSUFFICIENT_COLLATERAL");
        
        user_borrowed_usdc[msg.sender] += _amount;
        total_deposited[address(usdc)] -= _amount;
        IERC20(_token).transfer(msg.sender, _amount);
    }

    function repay(address _token, uint256 _amount) external { // 상환
        update(msg.sender);
        require(user_borrowed_usdc[msg.sender] >= _amount, "EXCEEDS_AMOUNT_TOKEN_REPAY");
        require(IERC20(_token).balanceOf(msg.sender) >= _amount, "USER_INSUFFICIENT_TOKEN");
        require(IERC20(_token).allowance(msg.sender, address(this)) >= _amount, "INSUFFICIENT_ALLOWANCE");

        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        user_borrowed_usdc[msg.sender] -= _amount;
        total_deposited[address(usdc)] += _amount;
    }

    function withdraw(address _token, uint256 _amount) external {
        update(msg.sender);

        uint ETH_PRICE = priceOraclce.getPrice(address(0));
        uint USDC_PRICE = priceOraclce.getPrice(address(usdc));
        
        uint user_deposited_price = ETH_PRICE * deposit_ether[msg.sender] + USDC_PRICE * deposit_usdc[msg.sender];
        uint user_current_debt_price = USDC_PRICE * user_borrowed_usdc[msg.sender];        
        uint user_withdraw_value = _amount * (_token == address(0) ? ETH_PRICE : USDC_PRICE);

        require(user_deposited_price - user_withdraw_value >= user_current_debt_price * 100 / 75, "LTV_FAILED");
        if (_token == address(0))
        {
            payable(msg.sender).call{value: _amount}("");
        }
        else 
        {
            require(IERC20(_token).balanceOf(address(this)) > _amount, "INSUFFICIENT_VAULT_BALANCE");
            IERC20(_token).transfer(msg.sender, _amount);
        }
    }

    function getAccruedSupplyAmount(address _token) external returns (uint256 accruedSupply) {

    }

    function liquidate(address _user, address _token, uint256 _amount) external {
        
    }

    function update(address _user) internal {
        uint last_update_block = last_update[_user];
        if (last_update_block == 0)
        {
            last_update[_user] = block.number;
            return;
        }
        uint256 borrowed = user_borrowed_usdc[_user];
        uint256 time_gap = block.number - last_update_block;
        emit logging(time_gap, time_gap);
        for(uint256 i = 0; i < time_gap; i++)
        {
            uint interest_per_block = borrowed * interest_rate / 10000;
            borrowed += interest_per_block;
        }
        user_borrowed_usdc[_user] = borrowed;
        last_update[_user] = block.number;
    }
}