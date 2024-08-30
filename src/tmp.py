user_3_deposit = 30000000
user_1_depoist = 100000000
total_deposit = user_1_depoist + user_3_deposit

total_debt = 0
interest_rate = 0.001

user_2_borrowed = 2000
total_debt += user_2_borrowed

accrued_interest = user_2_borrowed * ((1 + interest_rate) ** 1000 - 1) * user_3_deposit / total_deposit
print(accrued_interest)

accrued_interest = user_2_borrowed * ((1 + interest_rate) ** 1500 - 1) * user_3_deposit / total_deposit
print(accrued_interest)

##############################################################################################################

user_3_deposit = 30000000
user_1_depoist = 100000000
user_3_interest_rate = 0
total_deposit = user_1_depoist + user_3_deposit

total_debt = 0
interest_rate = 0.001

user_2_borrowed = 2000
total_debt += user_2_borrowed

user_3_interest_rate = (1 + interest_rate) ** 1000 - 1
accrued_interest = total_debt * user_3_interest_rate * user_3_deposit / total_deposit
print(accrued_interest)

user_4_deposit = 10000000
total_deposit += user_4_deposit


accrued_interest += total_debt * ((1 + interest_rate) ** 1500 - (1 + interest_rate) ** 1000) * user_3_deposit / total_deposit
print(accrued_interest)


user_3_interest_rate = (1 + interest_rate) ** 1000 - 1
print(user_3_interest_rate)
user_3_interest_rate = (1 + interest_rate) ** 1500 - 1
print(user_3_interest_rate)
user_3_interest_rate = (1 + interest_rate) ** 1500 - (1 + interest_rate) ** 1000 
print(user_3_interest_rate) 

##############################################################################################################
