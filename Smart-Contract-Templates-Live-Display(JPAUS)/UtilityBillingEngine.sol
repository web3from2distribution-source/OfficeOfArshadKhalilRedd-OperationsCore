[Contract Address: 0xFef964E9cF2EC888f83a7276F68EbdD4Bca9b67f] 

// SPDX-License-Identifier: MIT
/*
                        @@@@@@@@@@
                  @@@@@@@     ..  @@@@@@@
              @@@@+ .=    #@@ @@ .   @  @@@@
           @@@-  : @.@.   :         .: @@@  @@@
         @@@  *@@ .    @@@. -=%=          @ @ =@@
       @@@ :   .    @%..  -:= %@@@@@%+     + :@+.@@
      @@. @#-. :.  @#- -@ %=        @@....      +%@@
    @@@  @@  .... @=.#:==*=##+:++:-:     ..... =@  :@@
   @@@      ..... @%- :#:  .:-+*%%-     ... ...     .@@
  @:@  .......... @@ # *%@#@@%*-%%@@@@@ ............  @@
  @@  .........   @@=@@# .: =            .......... . :@
 @@  ............  @@=.=@ -**@@@@+    =.  ............ @@       https://takeapenny.vercel.app
 @@  ...........   .@#: =@=      @@@#*@@@ . .......... .@
@@: ......... ....  @@=*.  %-. .= .-+@.   . ... . .... .@@    Turn "down bad" into "down notsobad"
@%. .........  .     *@*=*:.@@#          .. . ....... . @@
@*                   +. . *=:+@@@*.  .+. ........ ....  @@
@# @ *@@@@-@@+@.#@  #%=##  :  =-+:@@@@@  ........ ....  @@   Exhaustive value tool for EVM/SOL Wallets
@@ *@# @.*@ =..- = *@.  -%@- .. :*-     .....  ....... .@@      that finds EVERY penny in value.
 @.               @@*=#%% .+@@ :.     .             .. .@
 *@  .... ...    @%   .  :@ .#@= @@@@    @@ @@ @ @@ .  @@
  @% ........   @#-#++:=@@ -:.@@*        %@ @@ @ .@   @@
  @@*   ....   @.     #@  :@   @.+  @:.          .   @@@
   @@+  ....  @:.=*#@%- @@. @  -@*#. :- :   :@@     +@@
     @%      @@=@*%*:-*.  @@.@   @+++ =@%:@  .@    @@
      @@.   .% =*@+.@@-.@  =:+@   @:# +  =-+@    -%@
       @@@   @@*    =%%@@#- %-@:. =.=* -@  : @- @@@
         @@@    @@@.    :#@@-%@@*@@@@@- :%@@  =@@
           @@@-    @@@@*.     @@. @  :@@@  @@@@
              @@@@      @@@@@@@@@@.*    #@@@
                 .@@@@@+          =@@@@@+
                        +@@@@@@@@*
*/
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title UtilityBillingEngine
 * @notice Billing rate: $0.30 per 1,000,000 credits paid in jPAUSD.
 */
contract UtilityBillingEngine is AccessControl {
    bytes32 public constant AI_OPERATOR_ROLE = keccak256("AI_OPERATOR_ROLE");
    
    IERC20 public immutable jPAUSD;
    
    // Rate: $0.30 (30 cents) = 0.30 jPAUSD per 1,000,000 credits
    // In 18 decimals: 0.30 * 1e18 = 300,000,000,000,000,000 wei per 1,000,000 credits
    // Price per individual credit = 300,000,000,000 wei (0.0000003 jPAUSD)
    uint256 public constant COST_PER_CREDIT_WEI = 300000000000;
    
    address public treasury;

    event BillingExecuted(address indexed user, uint256 creditsConsumed, uint256 jPAUSDDeducted);

    constructor(address _jPAUSD, address _treasury, address _admin) {
        jPAUSD = IERC20(_jPAUSD);
        treasury = _treasury;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /**
     * @notice Calculates jPAUSD cost for a given number of execution credits.
     */
    function calculateCost(uint256 creditAmount) public pure returns (uint256) {
        return creditAmount * COST_PER_CREDIT_WEI;
    }

    /**
     * @notice Deducts billing fees in jPAUSD for AI worker execution tasks.
     */
    function billUtilityUsage(address user, uint256 creditAmount) external returns (bool) {
        uint256 cost = calculateCost(creditAmount);
        require(jPAUSD.balanceOf(user) >= cost, "UtilityBilling: Insufficient jPAUSD balance");

        bool success = jPAUSD.transferFrom(user, treasury, cost);
        require(success, "UtilityBilling: Fee deduction failed");

        emit BillingExecuted(user, creditAmount, cost);
        return true;
    }
}
