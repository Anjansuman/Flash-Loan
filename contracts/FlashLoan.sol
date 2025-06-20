// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Router01.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "./libraries/SafeERC20.sol";

// these all are made for binance smart chain, not for ethereum

contract FlashLoan {
    using SafeERC20 for IERC20;

    // pancake contracts
    address private constant PANCAKE_FACTORY =
        0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    address private constant PANCAKE_ROUTER =
        0x10ED43C718714eb63d5aA57B78B54704E256024E;

    // token addresses in BSC, these will be used to flash loan, the original swap contains all the tokens
    address private constant BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address private constant CROX = 0x2c094F5A7D1146BB93850f629501eB749f6Ed491;
    address private constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;

    // extras
    uint256 private deadline = block.timestamp + 1 days;
    uint256 private MAX_INT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;

    // this is for taking a loan with token and how much the loan will be
    function initiateArbitrage(address _tokenBorrow, uint256 _amount) external {
        // these are basically giving access to Pancake swap to spend the max value from these tokens
        IERC20(BUSD).safeApprove(address(PANCAKE_ROUTER), MAX_INT);
        IERC20(WBNB).safeApprove(address(PANCAKE_ROUTER), MAX_INT);
        IERC20(CAKE).safeApprove(address(PANCAKE_ROUTER), MAX_INT);

        // this will return if there's a liquidity available for these two tokens
        address pair = IUniswapV2Factory(PANCAKE_FACTORY).getPair(
            _tokenBorrow,
            WBNB
        );

        // address(0) means nothing in the address
        require(pair != address(0), "Liquidity pool doesn't exist");

        // these are basically checks that is done to verify the right tokens
        address token0 = IUniswapV2Pair(pair).token0(); // this will be my tokens address
        address token1 = IUniswapV2Pair(pair).token1(); // this will be WBNB (which I've entered for pool pair)

        // this is to check and store, on which token we got the loan
        uint amount0Out = _tokenBorrow == token0 ? _amount : 0;
        uint amount0Out = _tokenBorrow == token1 ? _amount : 0;

        //
        bytes memory data = abi.encode(_tokenBorrow, _amount, msg.sender);

        //
        IUniswapV2Pair(pair).swap(amount0Out, amount0Out, data);
    }

    function pancakeCall(address _sender, uint _amount0, uint _amount1, bytes calldata data) external {

        // here the msg.sender is the Uniswap pair contract for the pool that was found
        address token0 = IUniswapV2Pair(msg.sender).token0();
        address token1 = IUniswapV2Pair(msg.sender).token1();

        // again fetching the pool address
        address gotPair = IUniswapV2Factory(PANCAKE_FACTORY).getPair(token0, token1);

        // checking if both of them are equal
        requrie(msg.sender == gotPair, "both pairs didn't match");

        // the sender must be this contract
        require(_sender == address(this), "Sender must be this contract address");

        // this is to decode the data back to variables
        (address _tokenBorrow, uint256 _amount, address userAddress) = abi.decode(_data, (address, uint256, address));

        // fee calculation
        uint256 fee = ((amount * 3) / 997) + 1; // this fee is calculated as per pancake swap flash loans, can be changed as per other orgs
        uint256 repayAmount = _amount + fee;

        uint loanAmount = _amount0 > 0 ? _amount0 : _amount1;

        // Placing Triangular Arbitrage [I am assuming the user chose BUSD for it's loan, so I'm hardcoding others coins for trade]
        uint trade1Coin = placeTrade(BUSD, CROX, loanAmount);
        uint trade2Coin = placeTrade(CROX, CAKE, trade1Coin);
        uint trade3Coin = placeTrade(CAKE, BUSD, trade2Coin);

        // checking profit or loss
        bool result = checkResult(repayAmount, trade3Coin);

        require(result, "Loss occured, reverting!");

        // passed the required statement, that means profit occured

        // transfering profit amount to user
        IERC20(BUSD).transfer(userAddress, trade3Coin - repayAmount);
        IERC20(_tokenBorrow).transfer(gotPair, repayAmount);

    }

    function placeTrade(address _fromToken, address _toToken, uint amountIn) private returns(uint) {
        address pair = IUniswapV2Factory(PANCAKE_FACTORY).getPair(_fromToken, _toToken);
        
        require(pair != address(0), "Pool does not exist");

        address[] memory path = new address[](2); // array of size 2

        path[0] = _fromToken;
        path[1] = _toToken;

        uint amountRequired = IUniswapV2Router01(PANCAKE_FACTORY).getAmountsOut(amountIn, path[1]);

        uint amountReceived = IUniswapV2Router01(PANCAKE_ROUTER).swapExactTokensForTokens(amountIn, amountRequired, path, address(this), deadline)[1];

        require(amountReceived > 0, "Transaction aborted!");
        return amountReceived;
    }

    function checkResult(uint repayAmount, uint tradeAmount) private returns(bool) {
        return repayAmount > tradeAmount;
    }

    function getBalanceOfToken(address _address) public returns(uint) {
        reutrn IERC20(_address).balanceOf(address(this));
    }
}
