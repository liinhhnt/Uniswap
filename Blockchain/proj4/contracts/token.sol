// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

 
contract Token is Ownable, ERC20 {
    string private constant _symbol = 'NTL';                 
    string private constant _name = 'NtlDex';                

    bool private mintingDisable;
    
    constructor() ERC20(_name, _symbol) {
        mintingDisable = false;
    }

    function mint(uint amount) 
        public 
        onlyOwner
    {
        require(!mintingDisable, "Minting has been disabled");
        _mint(msg.sender, amount);
    }

    function disable_mint()
        public
        onlyOwner
    {
        mintingDisable = true;
    }
}