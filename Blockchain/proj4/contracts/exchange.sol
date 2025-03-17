// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;


import './token.sol';
import "hardhat/console.sol";


contract TokenExchange is Ownable {
    string public exchange_name = 'Hello NT Liinhh ne';

    address tokenAddr = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    Token public token = Token(tokenAddr);                                

    // Liquidity pool for the exchange
    uint private token_reserves = 0;
    uint private eth_reserves = 0;

    // Fee Pools
    uint private token_fee_reserves = 0;
    uint private eth_fee_reserves = 0;

    // Liquidity pool shares
    mapping(address => uint) private lps;

    // For Extra Credit only: to loop through the keys of the lps mapping
    address[] private lp_providers;      

    // Total Pool Shares
    uint private total_shares = 0;

    // liquidity rewards
    uint private swap_fee_numerator = 3;                
    uint private swap_fee_denominator = 100;

    // Constant: x * y = k
    uint private k;

    uint private multiplier = 10**5;

    constructor() {}
    

    // Function createPool: Initializes a liquidity pool between your Token and ETH.
    // ETH will be sent to pool in this transaction as msg.value
    // amountTokens specifies the amount of tokens to transfer from the liquidity provider.
    // Sets up the initial exchange rate for the pool by setting amount of token and amount of ETH.
    function createPool(uint amountTokens)
        external
        payable
        onlyOwner
    {
        // This function is already implemented for you; no changes needed.

        // require pool does not yet exist:
        require (token_reserves == 0, "Token reserves was not 0");
        require (eth_reserves == 0, "ETH reserves was not 0.");

        // require nonzero values were sent
        require (msg.value > 0, "Need eth to create pool.");
        uint tokenSupply = token.balanceOf(msg.sender);
        require(amountTokens <= tokenSupply, "Not have enough tokens to create the pool");
        require (amountTokens > 0, "Need tokens to create pool.");

        token.transferFrom(msg.sender, address(this), amountTokens);
        token_reserves = token.balanceOf(address(this));
        eth_reserves = msg.value;
        k = token_reserves * eth_reserves;

        // Pool shares set to a large value to minimize round-off errors
        total_shares = 10**5;
        // Pool creator has some low amount of shares to allow autograder to run
        lps[msg.sender] = 100;
    }

    // For use for ExtraCredit ONLY
    // Function removeLP: removes a liquidity provider from the list.
    // This function also removes the gap left over from simply running "delete".
    function removeLP(uint index) private {
        require(index < lp_providers.length, "specified index is larger than the number of lps");
        lp_providers[index] = lp_providers[lp_providers.length - 1];
        lp_providers.pop();
    }

    // Function getSwapFee: Returns the current swap fee ratio to the client.
    function getSwapFee() public view returns (uint, uint) {
        return (swap_fee_numerator, swap_fee_denominator);
    }

    // Function getReserves
    function getReserves() public view returns (uint, uint) {
        return (eth_reserves, token_reserves);
    }

    // ============================================================
    //                    FUNCTIONS TO IMPLEMENT
    // ============================================================
    
    /* ========================= Liquidity Provider Functions =========================  */ 

    // Function addLiquidity: Adds liquidity given a supply of ETH (sent to the contract as msg.value).
    // You can change the inputs, or the scope of your function, as needed.
    function addLiquidity(uint max_exchange_rate, uint min_exchange_rate) 
    external 
    payable
    {
        require(msg.value > 0, "ETH amount must be greater than 0");

        // Check if the caller has enough ETH
        uint totalEth = msg.sender.balance;
        require(msg.value < totalEth, "Insufficient ETH balance");

        // Calculate the current exchange rate (tokens per ETH)
        uint currentExchangeRate = (token_reserves * multiplier * 10**18) / eth_reserves ;

        // Ensure the current exchange rate is within the allowed range
        require(currentExchangeRate <= max_exchange_rate, "Exchange rate exceeds the maximum allowed");
        require(currentExchangeRate >= min_exchange_rate, "Exchange rate is below the minimum allowed");

        // Calculate the required amount of tokens based on the current ratio
        uint tokenAmount = msg.value * token_reserves / eth_reserves;

        // Check if the caller has enough tokens
        uint tokenSupply = token.balanceOf(msg.sender);
        require(tokenAmount <= tokenSupply, "Insufficient token balance");

        // Transfer tokens from the caller to the contract
        token.transferFrom(msg.sender, address(this), tokenAmount);

        // Update reserves and constant k
        eth_reserves += msg.value;
        token_reserves += tokenAmount;
        k = eth_reserves * token_reserves;

        // Update liquidity provider shares
        uint newShares = (total_shares * msg.value) / eth_reserves;
        lps[msg.sender] += newShares;
        total_shares += newShares;

        // Record the new liquidity provider
        if (lps[msg.sender] == newShares) lp_providers.push(msg.sender);
    }

    // Function removeLiquidity: Removes liquidity given the desired amount of ETH to remove.
    // You can change the inputs, or the scope of your function, as needed.
    function removeLiquidity(uint amountETH, uint max_exchange_rate, uint min_exchange_rate)
        public 
        payable
    {
        require(amountETH > 0, "ETH amount must be greater than 0");
        
        // Calculate the current exchange rate (tokens per ETH)
        uint currentExchangeRate = (token_reserves * multiplier * 10**18) / eth_reserves;

        // Ensure the current exchange rate is within the allowed range
        require(currentExchangeRate <= max_exchange_rate, "Exchange rate exceeds the maximum allowed");
        require(currentExchangeRate >= min_exchange_rate, "Exchange rate is below the minimum allowed");

        uint amountShare = total_shares * amountETH / eth_reserves;
        require(lps[msg.sender] >= amountShare, "Insufficient shares");
        require(amountETH < eth_reserves, "Cannot remove all the ETH reserves");
        uint amountToken = amountETH * token_reserves / eth_reserves;
        require(eth_reserves - amountETH >= 1 && token_reserves - amountToken >= 1, "Pool depletion");

        // Cal fee reward
        uint tokens_fee_rewards = amountShare * token_fee_reserves / total_shares;
        uint eth_fee_rewards = amountShare * eth_fee_reserves / total_shares;

        console.log("Remove liquidity: ", amountETH, amountToken);
        console.log("Fee rewards: ", eth_fee_rewards, tokens_fee_rewards);
        console.log(address(this).balance);
        console.log(token.balanceOf(address(this)));


        // Transfer ETH and tokens to the caller
        payable(msg.sender).transfer(amountETH + eth_fee_rewards);
        token.transfer( msg.sender, amountToken + tokens_fee_rewards);

        // Update reserves and shares
        eth_reserves -= amountETH;
        token_reserves -= amountToken;
        k = eth_reserves * token_reserves;
        lps[msg.sender] -= amountShare;
        total_shares -= amountShare;
    }

    // Function removeAllLiquidity: Removes all liquidity that msg.sender is entitled to withdraw
    // You can change the inputs, or the scope of your function, as needed.
    function removeAllLiquidity(uint max_exchange_rate, uint min_exchange_rate)
        external
        payable
    {
        // Calculate the current exchange rate (tokens per ETH)
        uint currentExchangeRate = (token_reserves * multiplier * 10**18) / eth_reserves;

        // Ensure the current exchange rate is within the allowed range
        require(currentExchangeRate <= max_exchange_rate, "Exchange rate exceeds the maximum allowed");
        require(currentExchangeRate >= min_exchange_rate, "Exchange rate is below the minimum allowed");

        uint shares = lps[msg.sender];
        require(shares > 0, "No liquidity available");
        uint amountETH = (shares * eth_reserves) / total_shares;
        uint amountTokens = (shares * token_reserves) / total_shares;
        require(eth_reserves - amountETH >= 1 && token_reserves - amountTokens >= 1, "Pool depletion");

        // Cal fee reward
        uint tokens_fee_rewards = shares * token_fee_reserves / total_shares;
        uint eth_fee_rewards = shares * eth_fee_reserves / total_shares;

        // Update reserves and shares
        eth_reserves -= amountETH;
        token_reserves -= amountTokens;
        k = eth_reserves * token_reserves;
        total_shares -= shares;
        lps[msg.sender] = 0;

        // Transfer ETH and tokens to the caller
        payable(msg.sender).transfer(amountETH + eth_fee_rewards);
        token.transfer(msg.sender, amountTokens + tokens_fee_rewards);
    }
    /***  Define additional functions for liquidity fees here as needed ***/


    /* ========================= Swap Functions =========================  */ 

    // Function swapTokensForETH: Swaps your token with ETH
    // You can change the inputs, or the scope of your function, as needed.
    function swapTokensForETH(uint amountTokens, uint max_exchange_rate)
        external 
        payable
    {        
        require(amountTokens > 0, "Token amount must be greater than 0");
        require(amountTokens <= token.balanceOf(msg.sender), "Trader does not have enough tokens!");
        
        uint tokenFee = amountTokens * swap_fee_numerator / swap_fee_denominator;
        uint swapTokens = amountTokens - tokenFee;
        uint amountETH = (eth_reserves * swapTokens) / (token_reserves + swapTokens);
        require(eth_reserves - amountETH >= 1, "Insufficient ETH in pool");
        
        // cal rate base on swapTokens or amountTokens???
        uint actualExchangeRate = (amountTokens * multiplier) / amountETH;
        require(actualExchangeRate <= max_exchange_rate, "Exchange rate exceeds the maximum");
        
        // swap token <-> eth
        token.transferFrom(msg.sender, address(this), amountTokens);
        payable(msg.sender).transfer(amountETH);

        // Update reserves
        eth_reserves -= amountETH;
        token_reserves += swapTokens; 

        token_fee_reserves += tokenFee;
    }

    // Function swapETHForTokens: Swaps ETH for your tokens
    // ETH is sent to contract as msg.value
    // You can change the inputs, or the scope of your function, as needed.
    function swapETHForTokens(uint max_exchange_rate)
        external
        payable 
    {
        require(msg.value > 0, "ETH amount must be greater than 0");
        require(msg.sender.balance >= msg.value, "Trader does not have enough ETH");
        
        uint ethFee = msg.value * swap_fee_numerator / swap_fee_denominator;
        uint swapEth = msg.value - ethFee;
        uint amountTokens = (token_reserves * swapEth) / (eth_reserves + swapEth);
        require(token_reserves - amountTokens >= 1, "Insufficient tokens in pool");

        uint actualExchangeRate = (amountTokens * multiplier) / msg.value;
        require(actualExchangeRate <= max_exchange_rate, "Exchange rate exceeds the maximum"); 

        // Update reserves
        eth_reserves += swapEth;
        token_reserves -= amountTokens;
        eth_fee_reserves += ethFee;

        // Transfer tokens to the caller
        token.transfer(msg.sender, amountTokens);
    }
}
