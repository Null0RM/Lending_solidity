// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPriceOracle {
    function getPrice(address token) external view returns (uint256);
    function setPrice(address token, uint256 price) external;
}

contract UpsideLending {
    struct User {
        bool isInit;
        uint deposit_eth;
        uint deposit_usdc;
        uint borrow_usdc;
        uint last_accrued_interest;
        uint debt_update_time;
        uint deposit_update_time;
    }

    // oracle related
    IPriceOracle priceOracle;
    address usdc;

    // user related
    mapping(address => User) private user_info;
    address[] private users;

    // protocol vault related
    uint total_deposited_ETH;
    uint total_deposited_USDC;
    uint total_borrowed;

    // helper variables
    bool initialized;
    uint short_numerator = 10000001388195003; // for block unit
    uint short_denominator = 1e16;
    uint numerator = 1001;
    uint denominator = 1000;

    // initialized only once
    modifier onlyOnce() {
        require(initialized == false, "ALREADY_INITIALIZED");
        _;
        initialized = true;
    } 

    constructor(IPriceOracle _oracle, address _usdc) {
        priceOracle = _oracle;
        usdc = _usdc;
    }

    function initializeLendingProtocol(address _usdc) external payable onlyOnce {
        usdc = _usdc;
        require(IERC20(usdc).balanceOf(msg.sender) >= msg.value, "USER_INSUFFICEINT_AMOUNT_USDC");
        require(IERC20(usdc).allowance(msg.sender, address(this)) >= msg.value, "USER_INSUFFICEINT_ALLOWANCE_USDC");        
        IERC20(usdc).transferFrom(msg.sender, address(this), msg.value);

        total_deposited_ETH += msg.value;
        total_deposited_USDC += msg.value;
    }
    
    function deposit(address _token, uint256 _depositAmount) external payable {
        _debtUpdate(msg.sender);
        User memory user = user_info[msg.sender];

        if (user.isInit == false) {
            user.isInit = true;
            users.push(msg.sender);
            user.debt_update_time = block.number;
            user.deposit_update_time = block.number;
        }
        
        if (_token == address(0)) {
            require(_depositAmount == msg.value, "ARG_AND_RECEIVED_ETHER_MISMATCH");
            user.deposit_eth += _depositAmount;
            total_deposited_ETH += _depositAmount;
        }
        else {
            require(IERC20(usdc).balanceOf(msg.sender) >= _depositAmount, "INSUFFICIENT_BALANCE");
            require(IERC20(usdc).allowance(msg.sender, address(this)) >= _depositAmount, "INSUFFICIENT_ALLOWANCE");
            IERC20(usdc).transferFrom(msg.sender, address(this), _depositAmount);
            user.deposit_usdc += _depositAmount;
            total_deposited_USDC += _depositAmount;
        }

        user_info[msg.sender] = user;
        _depositUpdate();
    }

    function borrow(address _token, uint256 _amount) external {
        require(_token == address(usdc), "ONLY_USDC_AVAILABLE");
        _debtUpdate(msg.sender);
        User memory user = user_info[msg.sender];
        
        // oracle
        uint ETH_PRICE = priceOracle.getPrice(address(0));
        uint USDC_PRICE = priceOracle.getPrice(address(usdc));
        // calc
        uint user_deposit_value = ETH_PRICE * user.deposit_eth + USDC_PRICE * user.deposit_usdc;
        uint user_borrow_price = USDC_PRICE * _amount;
        uint user_cur_debt_price = USDC_PRICE * user.borrow_usdc;
        require(user_deposit_value >= (user_borrow_price + user_cur_debt_price) * 2, "INSUFFICIENT_DEPOSIT");
        
        user.borrow_usdc += _amount;
        total_borrowed += _amount;
        IERC20(_token).transfer(msg.sender, _amount);

        user_info[msg.sender] = user;
        _depositUpdate();
    }

    function repay(address _token, uint256 _amount) external {
        _debtUpdate(msg.sender);
        User memory user = user_info[msg.sender];

        require(user.borrow_usdc >= _amount, "EXCEEDS_AMOUNT_TOKEN_REPAY");
        require(IERC20(_token).balanceOf(msg.sender) >= _amount, "USER_INSUFFICIENT_TOKEN");
        require(IERC20(_token).allowance(msg.sender, address(this)) >= _amount, "INSUFFICIENT_ALLOWANCE");
        
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        user.borrow_usdc -= _amount;
        total_borrowed -= _amount;

        user_info[msg.sender] = user;
        _depositUpdate();
    }

    function withdraw(address _token, uint256 _amount) external {
        _debtUpdate(msg.sender);

        User memory user = user_info[msg.sender];

        uint ETH_PRICE = priceOracle.getPrice(address(0));
        uint USDC_PRICE = priceOracle.getPrice(address(usdc));
        
        uint user_deposited_value = ETH_PRICE * user.deposit_eth + USDC_PRICE * (user.deposit_usdc + user.last_accrued_interest);
        uint user_cur_debt_value = USDC_PRICE * user.borrow_usdc;        
        uint user_withdraw_value = _amount * (_token == address(0) ? ETH_PRICE : USDC_PRICE);

        require((user_deposited_value - user_withdraw_value) * 75 >= user_cur_debt_value * 100, "LTV_FAILED");
        if (_token == address(0))
        {
            require(address(this).balance >= _amount, "INSUFFICIENT_VAULT_BALANCE");
            (bool suc, ) = payable(msg.sender).call{value: _amount}("");
            require(suc, "ETH_TRANSFER_FAILED");
            user.deposit_eth -= _amount;
            total_deposited_ETH -= _amount;
        }
        else 
        {
            require(IERC20(_token).balanceOf(address(this)) >= _amount, "INSUFFICIENT_VAULT_BALANCE");
            IERC20(_token).transfer(msg.sender, _amount);
            user.deposit_usdc = user.deposit_usdc + user.last_accrued_interest - _amount;
            total_deposited_USDC -= _amount;
        }
        
        user_info[msg.sender] = user;
        _depositUpdate();
    }

    function liquidate(address _user, address _token, uint256 _amount) external {
        _debtUpdate(_user);
        User memory user = user_info[_user];
        
        uint ETH_PRICE = priceOracle.getPrice(address(0));
        uint USDC_PRICE = priceOracle.getPrice(address(usdc));

        uint user_deposited_value = ETH_PRICE * user.deposit_eth + USDC_PRICE * user.deposit_usdc;
        uint user_cur_debt_value = USDC_PRICE * user.borrow_usdc;  

        uint LTV = (user_cur_debt_value * 100) / user_deposited_value;
        
        require(LTV >= 75, "HEALTHY_LOAN");

        uint borrowed_amount =  user_deposited_value - user_cur_debt_value;
        uint max_liquidatable = user.borrow_usdc * 25 / 100;
        if (user.borrow_usdc < 100)
            max_liquidatable = user.borrow_usdc;
        
        require(max_liquidatable >= _amount, "EXCEEDS_MAX_LIQUIDATABLE_AMOUNT");

        uint liquidatable_collateral = (USDC_PRICE * _amount) / ETH_PRICE;
        (bool suc, ) = msg.sender.call{value: liquidatable_collateral}("");                
        require(suc, "send ether failed");
        
        IERC20(usdc).transferFrom(msg.sender, address(this), _amount);

        user.borrow_usdc -= _amount;
        user.deposit_eth -= liquidatable_collateral;

        user_info[_user] = user;
        _depositUpdate();
    }

    function getAccruedSupplyAmount(address _token) external returns (uint256 accruedSupply) {
        _debtUpdate(msg.sender);
        _depositUpdate();
        User memory user = user_info[msg.sender];
        accruedSupply = user.deposit_usdc + user.last_accrued_interest;
    }

    function _debtUpdate(address _user) internal {
        User memory user = user_info[_user];
        if (!user.isInit)
            return;
        
        uint timeElapsed;
        timeElapsed = block.number - user.debt_update_time;

        user.borrow_usdc += _pow(user.borrow_usdc, timeElapsed, false);
        user.debt_update_time = block.number;

        user_info[_user] = user;
    }

    /**
     * 여기에서 계산해야할 것
        * principal * ((1.001) ** timeElapsed - (1.001) ** depositUpdateTime) * userDepositedUSDC / totalDepositedUSDC을 더해줌
     * 여기에서 추가해야할 것
     */
    function _depositUpdate() internal {
        uint length = users.length;
        uint timeElapsed;
        uint calc;
        uint i;
        User memory user;

        for(i = 0; i < length; i++) {
            user = user_info[users[i]];
            
            timeElapsed = (block.number - user.deposit_update_time) / 7200;
            if (timeElapsed == 0)
                continue;

            calc = _pow(total_borrowed, block.number / 7200 , true) - _pow(total_borrowed, user.deposit_update_time / 7200, true);
            calc = calc * user.deposit_usdc / total_deposited_USDC;
            user.last_accrued_interest += calc;

            user.deposit_update_time = block.number;
            user_info[users[i]] = user;
        }
    }

    function _pow(uint256 to_mult, uint256 exp, bool calc_type) internal returns (uint256 retVal) {
        uint tmp = to_mult;
        if (calc_type == false) {
            for(uint256 i = 0; i < exp; i++) {
                to_mult = to_mult * short_numerator / short_denominator;
            }
        }
        else {
            for(uint256 i = 0; i < exp; i++) {
                to_mult = to_mult * numerator / denominator;
            }
        }
        retVal = to_mult - tmp;
    }
}