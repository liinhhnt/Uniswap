// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;


import './token.sol';
import "hardhat/console.sol";


contract TokenExchange is Ownable {
    string public exchange_name = 'Hello NT Liinhh ne';

    address tokenAddr = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512;
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
    function addLiquidity() 
    external 
    payable
    {
        require(msg.value > 0, "ETH amount must be greater than 0");

        // Check if the caller has enough ETH
        uint totalEth = msg.sender.balance;
        require(msg.value < totalEth, "Insufficient ETH balance");

        // Calculate the required amount of tokens based on the current ratio
        uint tokenAmount = msg.value * token_reserves / eth_reserves;

        // Check if the caller has enough tokens
        uint tokenSupply = token.balanceOf(msg.sender);
        require(tokenAmount <= tokenSupply, "Insufficient token balance");

        // Log the contract's ETH balance before receiving the new liquidity
        uint contractBalanceBefore = address(this).balance;

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
        lp_providers.push(msg.sender);

        // Log the contract's ETH balance after receiving the new liquidity
        uint contractBalanceAfter = address(this).balance;
        require(contractBalanceAfter == contractBalanceBefore + msg.value, "ETH not transferred correctly");
    }

    // Function removeLiquidity: Removes liquidity given the desired amount of ETH to remove.
    // You can change the inputs, or the scope of your function, as needed.
    function removeLiquidity(uint amountETH)
        public 
        payable
    {
        require(amountETH > 0, "ETH amount must be greater than 0");
        uint amountShare = total_shares * amountETH / eth_reserves;
        require(lps[msg.sender] >= amountShare, "Insufficient shares");
        require(amountETH < eth_reserves, "Cannot remove all the ETH reserves");
        uint amountToken = amountETH * token_reserves / eth_reserves;
        require(eth_reserves - amountETH > 0 && token_reserves - amountToken > 0, "Pool depletion");

        // Transfer ETH and tokens to the caller
        payable(msg.sender).transfer(amountETH);
        token.transferFrom(address(this), msg.sender, amountToken);

        // Update reserves and shares
        eth_reserves -= amountETH;
        token_reserves -= amountToken;
        k = eth_reserves * token_reserves;
        lps[msg.sender] -= amountShare;
        total_shares -= amountShare;
    }

    // Function removeAllLiquidity: Removes all liquidity that msg.sender is entitled to withdraw
    // You can change the inputs, or the scope of your function, as needed.
    function removeAllLiquidity()
        external
        payable
    {
        uint shares = lps[msg.sender];
        require(shares > 0, "No liquidity available");
        uint amountETH = (shares * eth_reserves) / total_shares;
        uint amountTokens = (shares * token_reserves) / total_shares;
        require(eth_reserves - amountETH > 0 && token_reserves - amountTokens > 0, "Pool depletion");

        // Update reserves and shares
        eth_reserves -= amountETH;
        token_reserves -= amountTokens;
        k = eth_reserves * token_reserves;
        total_shares -= shares;
        lps[msg.sender] = 0;

        // Transfer ETH and tokens to the caller
        payable(msg.sender).transfer(amountETH);
        token.transfer(msg.sender, amountTokens);
    }
    /***  Define additional functions for liquidity fees here as needed ***/


    /* ========================= Swap Functions =========================  */ 

    // Function swapTokensForETH: Swaps your token with ETH
    // You can change the inputs, or the scope of your function, as needed.
    function swapTokensForETH(uint amountTokens)
        external 
        payable
    {
        /******* TODO: Implement this function *******/
        require(amountTokens > 0, "Token amount must be greater than 0");
        uint ethAmount = (eth_reserves * amountTokens) / (token_reserves + amountTokens);
        require(eth_reserves - ethAmount >= 1, "Insufficient ETH in pool");

        // Transfer tokens to the contract
        token.transferFrom(msg.sender, address(this), amountTokens);

        // Update reserves
        eth_reserves -= ethAmount;
        token_reserves += amountTokens;
        k = eth_reserves * token_reserves;

        // Transfer ETH to the caller
        payable(msg.sender).transfer(ethAmount);
    }



    // Function swapETHForTokens: Swaps ETH for your tokens
    // ETH is sent to contract as msg.value
    // You can change the inputs, or the scope of your function, as needed.
    function swapETHForTokens()
        external
        payable 
    {
        /******* TODO: Implement this function *******/
        require(msg.value > 0, "ETH amount must be greater than 0");
        uint tokenAmount = (token_reserves * msg.value) / (eth_reserves + msg.value);
        require(token_reserves - tokenAmount >= 1, "Insufficient tokens in pool");

        // Update reserves
        eth_reserves += msg.value;
        token_reserves -= tokenAmount;
        k = eth_reserves * token_reserves;

        // Transfer tokens to the caller
        token.transfer(msg.sender, tokenAmount);
    }
}

// function swapTokensForETH(uint256 amountTokens) external payable {
//         require(amountTokens > 0, "Amount must be greater than 0");
//         require(token.balanceOf(msg.sender) >= amountTokens, "Insufficient token balance");

//         // Calculate the amount of ETH to send
//         uint256 amountETH = (amountTokens * ethReserves) / tokenReserves;

//         // Ensure the pool is not drained to zero
//         require(ethReserves - amountETH > 0, "Cannot drain ETH reserves");
//         require(tokenReserves + amountTokens > 0, "Cannot drain token reserves");

//         // Update reserves
//         ethReserves -= amountETH;
//         tokenReserves += amountTokens;

//         // Transfer tokens from the user to the contract
//         token.transferFrom(msg.sender, address(this), amountTokens);

//         // Transfer ETH to the user
//         payable(msg.sender).transfer(amountETH);

//         emit TokensSwappedForETH(msg.sender, amountTokens, amountETH);
//     }

//     /**
//      * @dev Swaps ETH for tokens.
//      */
//     function swapETHForTokens() external payable {
//         require(msg.value > 0, "ETH amount must be greater than 0");

//         // Calculate the amount of tokens to send
//         uint256 amountTokens = (msg.value * tokenReserves) / ethReserves;

//         // Ensure the pool is not drained to zero
//         require(tokenReserves - amountTokens > 0, "Cannot drain token reserves");
//         require(ethReserves + msg.value > 0, "Cannot drain ETH reserves");

//         // Update reserves
//         ethReserves += msg.value;
//         tokenReserves -= amountTokens;

//         // Transfer tokens to the user
//         token.transfer(msg.sender, amountTokens);

//         emit ETHSwappedForTokens(msg.sender, msg.value, amountTokens);
//     }