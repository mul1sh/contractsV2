/**
 * Copyright 2017-2020, bZeroX, LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0.
 */

// SPDX-License-Identifier: GNU 
pragma solidity 0.6.12;

import "../core/State.sol";
import "../openzeppelin/SafeERC20.sol";
import "../feeds/IPriceFeeds.sol";
import "../events/FeesEvents.sol";
import "../mixins/ProtocolTokenUser.sol";


contract FeesHelper is State, ProtocolTokenUser, FeesEvents {
    using SafeERC20 for IERC20;

    // calculate trading fee
    function _getTradingFee(
        uint256 feeTokenAmount)
        internal
        view
        returns (uint256)
    {
        return feeTokenAmount
            .mul(tradingFeePercent)
            .div(10**20);
    }

    // calculate loan origination fee
    function _getBorrowingFee(
        uint256 feeTokenAmount)
        internal
        view
        returns (uint256)
    {
        return feeTokenAmount
            .mul(borrowingFeePercent)
            .div(10**20);
    }

    // settle trading fee
    function _payTradingFee(
        address user,
        bytes32 loanId,
        address feeToken,
        uint256 tradingFee)
        internal
    {
        if (tradingFee != 0) {
            tradingFeeTokensHeld[feeToken] = tradingFeeTokensHeld[feeToken]
                .add(tradingFee);

            emit PayTradingFee(
                user,
                feeToken,
                loanId,
                tradingFee
            );

            _payFeeReward(
                user,
                loanId,
                feeToken,
                tradingFee
            );
        }
    }

    // settle loan origination fee
    function _payBorrowingFee(
        address user,
        bytes32 loanId,
        address feeToken,
        uint256 borrowingFee)
        internal
    {
        if (borrowingFee != 0) {
            borrowingFeeTokensHeld[feeToken] = borrowingFeeTokensHeld[feeToken]
                .add(borrowingFee);

            emit PayBorrowingFee(
                user,
                feeToken,
                loanId,
                borrowingFee
            );

            _payFeeReward(
                user,
                loanId,
                feeToken,
                borrowingFee
            );
        }
    }

    // settle lender (interest) fee
    function _payLendingFee(
        address user,
        address feeToken,
        uint256 lendingFee)
        internal
    {
        if (lendingFee != 0) {
            lendingFeeTokensHeld[feeToken] = lendingFeeTokensHeld[feeToken]
                .add(lendingFee);

            emit PayLendingFee(
                user,
                feeToken,
                lendingFee
            );

             //// NOTE: Lenders do not receive a fee reward ////
        }
    }

    // settles and pays borrowers based on the fees generated by their interest payments
    function _settleFeeRewardForInterestExpense(
        LoanInterest storage loanInterestLocal,
        bytes32 loanId,
        address feeToken,
        address user,
        uint256 interestTime)
        internal
    {
        // this represents the fee generated by a borrower's interest payment
        uint256 interestExpenseFee = interestTime
            .sub(loanInterestLocal.updatedTimestamp)
            .mul(loanInterestLocal.owedPerDay)
            .div(86400)
            .mul(lendingFeePercent)
            .div(10**20);

        loanInterestLocal.updatedTimestamp = interestTime;

        if (interestExpenseFee != 0) {
            _payFeeReward(
                user,
                loanId,
                feeToken,
                interestExpenseFee
            );
        }
    }


    // pay potocolToken reward to user
    function _payFeeReward(
        address user,
        bytes32 loanId,
        address feeToken,
        uint256 feeAmount)
        internal
    {
        uint256 rewardAmount;
        address _priceFeeds = priceFeeds;
        (bool success, bytes memory data) = _priceFeeds.staticcall(
            abi.encodeWithSelector(
                IPriceFeeds(_priceFeeds).queryReturn.selector,
                feeToken,
                bzrxTokenAddress, // price rewards using BZRX price rather than vesting token price
                feeAmount / 2  // 50% of fee value
            )
        );
        assembly {
            if eq(success, 1) {
                rewardAmount := mload(add(data, 32))
            }
        }

        if (rewardAmount != 0) {
            address rewardToken;
            (rewardToken, success) = _withdrawProtocolToken(
                user,
                rewardAmount
            );
            if (success) {
                protocolTokenPaid = protocolTokenPaid
                    .add(rewardAmount);

                emit EarnReward(
                    user,
                    rewardToken,
                    loanId,
                    rewardAmount
                );
            }
        }
    }
}