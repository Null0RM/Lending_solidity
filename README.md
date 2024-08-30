# Upside Lending
* * *
## Oracle
> ### setPrice
- ETH 또는 usdc의 가격을 setting하는 함수.
> ### getPrice
- ETH또는 usdc의 가격을 get하는 함수

## Method

>### constructor   
컨트랙트 배포 시 초기화 로직
- Price Oracle
- usdc address

>### initializeLendingProtocol
Lending Pool의 reserve를 만들어주는 로직
- ETH
- usdc

>### deposit
자산(또는 담보)를 예치할 수 있으며, 이를 borrow해주게 되면, 이를 통해 이자를 얻을 수 있음.

- ETH   
    msg.value와 _depositAmount가 같아야 함
    user의 deposited_ETH를 늘려줌
    ETH의 총 deposit양을 증가
- usdc   
    ERC20이므로, allowance와 balance가 유저에게 충분한지 체크
    transferFrom을 통해 usdc를 UpsideLending으로 전송
    user의 deposited_usdc를 늘려줌
    usdc의 총 deposit양을 증가

- 결과   
    deposit으로 인한 lending protocol의 전체 deposit총량이 늘어나게 되며, 이로 인해 기존에 deposit을 했던 user가 얻게 되는 이자가 줄어들게 됨(이자 감산)
    이를 block.number를 이용하여 반영하도록 하는 로직을 추가해야 함. (test-case에서는 ETH의 양을 기준으로 잡고 있지는 않기 때문에, usdc만 고려해도 될 듯 함.)

>### borrow
msg.sender가 담보로 예치한 금액의 50%만큼의 usdc를 borrow할 수 있는 로직. **(LTV = 50%)**   
borrow에서, 이자율은 0.1% 복리이며 (/ 1 day(1 day == 72000 blocks)) 이를 통해 만들어진 이자는 deposit한 주체들의 이익으로 전환됨. (test case의 경우, 아직 갚지 않았더라도 deposit한 주체들에게 이자를 지급할 수 있음)

- 입력   
    _token: usdc의 주소   
    _amount: 빌릴 usdc의 총량

- 조건   
    지금까지 borrow한 usdc가 있다면, 이에 대한 이자까지 고려하여 LTV가 50을 넘지 않아야 대출 가능

- 결과   
    user의 borrow_usdc += _amount   
    total_borrowed += _amount   
    deposit한 user들의 현재까지 이자 계산 및 저장, block.number변경 유의

>### repay
borrow한 이자를 되갚는 함수
- 입력   
    _token: usdc
    _amount: repay총량

- 조건    
    지금까지 빌린 금액이 _amount보다 크거나 같아야 함.   
    user가 usdc에 대해 _amount만큼 approve, 및 잔액이 존재해야 함   

- 결과   
    transferFrom을 통해 user의 uscd를 _amount만큼 전송   
    user의 borrowed_usdc 감소   
    total_borrow_usdc 감소   
    deposit한 user들의 현재까지 이자 계산 및 저장, block.number변경 유의.   
    
>### withdraw
deposit해두었던 자산을 출금하는 함수
- 입력   
    _token: usdc or ETH
    _amount: 출금할 양   

- 조건
    user가 withdraw하려는 금액을 withdraw했을 때, LTV가 75% 아래로 떨어지면 안됨.   

- 결과   
    * ETH:    
        이더를 전송해줌
    * usdc:      
        usdc를 전송해줌    
        user의 deposited_usdc 감소   
        total_deposited_usdc 감소   
        deposit한 유저들의 현재까지 이자 계산 및 저장, block.number 변경 유의.

>### liquidate
청산 threshold = 75%. 즉, deposit한 자산 대비 부채의 비율이 75%를 넘어가게 된다면 청산을 실행시킬 수 있음.   
청산은 한 번 실행할 때 borrow한 총량의 25%까지만 청산을 실행할 수 있으며, 이 때는 예치된 담보를 팔아서 user에게 해당 양 만큼의 담보를 전송해줘야 함. borrow한 총량이 100 미만이 되면, 100%를 청산시킬 수 있음.

- 입력   
    _user: 청산시킬 user 의 주소   
    _token: 청산시킬 자산의 종류   
    _amount: 청산시킬 자산의 양   

- 조건   
    _user의 deposit한 총 금액 대비 부채 비율이 LTV를 넘지 않아야 함 (<= 75) -> 청산 실행 가능       
    _amount가 청산 가능한 최대 금액을 넘지않아야 함    

- 결과   
    ETH 전송   
    _user의 borrowed usdc 감소 -> 현재까지 이자 계산 및 저장 (이자 감산)   
    _user의 deposited ether 감소   
    msg.sender가 구매한 만큼의 usdc를 transferFrom   

>### getAccruedSupplyAmount

user가 lending에 보유하고 있는 총 자산을 나타냄.   
- 계산   
    principal: 원금   
    interest_rate: 0.001   
    $$accruedInterest = lastAccruedIntererst + \frac{principal \times (((1.001)^{timeElapsed}) - (1.001) ^{lastTimeElapsed}) \times userDeposited}{totalDepositedUSDC}$$
    
    
## Additional Methods

>### update
매 함수 호출 시 마다, 얻는 이자 및 대출이자 등을 고려하여 사용자의 자산에 변화를 주기 위한 함수   
- 변화 대상       
    부채에 대한 이자   
    담보에 대한 이자   
    * 부채에 대한 함수와 담보에 대한 함수를 따로 제작
