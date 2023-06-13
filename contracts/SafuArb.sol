// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

//https://github.com/burgossrodrigo

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

contract SafuuArbitrage {
    using SafeMath for uint256;

    constructor(address _weth) {
        weth = _weth;
    }

    struct User {
        mapping(address => uint256) userReward;
        mapping(address => uint256) userBalance;
    }

    address[] public users;

    address weth;
    uint256 public totalStaked;

    mapping(address => User) userData;
    mapping(address => bool) isUser;

    event ArbitrageExecuted(address token, uint256 profit);
    event Staked(address token, address sender, uint256 amount);
    event Withdrawn(
        address token,
        address sender,
        uint256 amount,
        uint256 rewardAmount
    );
    event RewardsCollected(address token, address sender, uint256 amount);

    function triangularArbitrage(
        address router,
        address token0,
        address token1,
        address token2,
        uint256 amount
    ) external returns (uint256 profit) {
        address[] memory path0 = new address[](2);
        path0[0] = token0;
        path0[1] = token1;

        address[] memory path1 = new address[](2);
        path1[0] = token1;
        path1[1] = token2;

        address contractAddress = address(this);

        uint256[] memory amount0 = IUniswapV2Router02(router).getAmountsOut(
            amount,
            path0
        );

        uint256[] memory amount1 = IUniswapV2Router02(router).getAmountsOut(
            amount,
            path1
        );

        if (amount0[1] < amount1[1]) {
            IUniswapV2Router02(router)
                .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    amount,
                    0,
                    path0,
                    contractAddress,
                    block.timestamp + 1200
                );

            IUniswapV2Router02(router)
                .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    amount0[1],
                    0,
                    path1,
                    contractAddress,
                    block.timestamp + 1200
                );
        }

        distributeRewards(token0, amount1[1]);
        emit ArbitrageExecuted(token0, amount1[1]);
        return amount1[1];
    }

    function stake(address _token, uint256 amount) external {
        address sender = msg.sender;
        address receiver = address(this);

        IERC20 token = IERC20(_token);
        uint256 allowance = token.allowance(sender, receiver);

        if (allowance > amount) {
            token.transferFrom(sender, receiver, amount);
            userData[sender].userBalance[_token].add(amount);
            totalStaked.add(amount);
            if (!isUser[sender]) {
                users.push(sender);
            }
        }
    }

    function withdraw(address token, uint256 amount) external {
        require(isUser[msg.sender], "User has no staked balance");
        require(
            userData[msg.sender].userBalance[token] >= amount,
            "Insufficient balance for withdrawal"
        );

        uint256 rewardAmount = userData[msg.sender].userReward[token];

        require(
            IERC20(token).transfer(msg.sender, amount),
            "Token transfer failed"
        );

        userData[msg.sender].userBalance[token] = userData[msg.sender]
            .userBalance[token]
            .sub(amount);
        userData[msg.sender].userReward[token] = rewardAmount.sub(amount);
        totalStaked.sub(amount);

        if (userData[msg.sender].userBalance[token] == 0) {
            isUser[msg.sender] = false;
        }

        emit Withdrawn(token, msg.sender, amount, rewardAmount);
    }

    function collectRewards(address token, uint256 amount) external {
        require(isUser[msg.sender], "User has no staked balance");

        uint256 rewardBalance = userData[msg.sender].userReward[token];
        require(rewardBalance >= amount, "Insufficient reward balance");

        require(
            IERC20(token).transfer(msg.sender, amount),
            "Token transfer failed"
        );

        userData[msg.sender].userReward[token] = rewardBalance.sub(amount);

        emit RewardsCollected(token, msg.sender, amount);
    }

    function distributeRewards(address token, uint256 rewardAmount) internal {
        require(users.length > 0, "No stakers to distribute rewards");
        require(rewardAmount > 0, "Reward amount must be greater than zero");

        require(
            totalStaked > 0,
            "Total staked amount must be greater than zero"
        );

        uint256 totalRewards = rewardAmount;
        uint256 paidRewards;

        for (uint256 i = 0; i < users.length; i++) {
            address stakerAddress = users[i];
            User storage staker = userData[stakerAddress];

            uint256 stakerBalance = staker.userBalance[token];
            if (stakerBalance > 0) {
                uint256 stakerRewards = totalRewards.mul(stakerBalance).div(
                    totalStaked
                );

                // Add rewards to staker's cumulative rewards
                staker.userReward[token] = staker.userReward[token].add(
                    stakerRewards
                );
                paidRewards = paidRewards.add(stakerRewards);
            }
        }
    }

    function getStakerCount() external view returns (uint256 stakersCount) {
        return users.length;
    }

    function getUserBalance(address user, address token) external view returns (uint256 userBalance) {
        return userData[user].userReward[token];
    }

    function getUserReward(address user, address token) external view returns (uint256 userReward) {
        return userData[user].userBalance[token];
    }
}
