[Contract Address: 0xa1441e1B4Bc3DF41113027D2a3b30CC8158aFf4D] 

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
 * @title InPlaceWrapper
 * @notice Manages state wrapping, asset collateral verification, and Class S/A/B/C grading.
 */
contract InPlaceWrapper is AccessControl {
    bytes32 public constant AI_OPERATOR_ROLE = keccak256("AI_OPERATOR_ROLE");

    enum UtilityClass { CLASS_C, CLASS_B, CLASS_A, CLASS_S }

    struct WrappedAsset {
        uint256 amountWrapped;
        uint256 collateralReserve;
        UtilityClass grade;
        bool isSegregated;
    }

    // Mapping of Sub-Token -> User -> State
    mapping(address => mapping(address => WrappedAsset)) public wrapperState;

    event AssetWrapped(address indexed user, address indexed subToken, uint256 amount, UtilityClass grade);
    event AssetUnwrapped(address indexed user, address indexed subToken, uint256 amount);

    constructor(address _admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /**
     * @notice Assigns Class S/A/B/C utility grade based on collateral ratio percentage.
     */
    function evaluateGrade(uint256 collateral, uint256 totalValue) public pure returns (UtilityClass) {
        if (totalValue == 0) return UtilityClass.CLASS_C;
        uint256 ratio = (collateral * 100) / totalValue;

        if (ratio >= 100) return UtilityClass.CLASS_S;
        if (ratio >= 75)  return UtilityClass.CLASS_A;
        if (ratio >= 50)  return UtilityClass.CLASS_B;
        return UtilityClass.CLASS_C;
    }

    /**
     * @notice Internal state wrapping mechanism.
     */
    function wrapAsset(address subToken, uint256 amount, uint256 collateral) external {
        IERC20(subToken).transferFrom(msg.sender, address(this), amount);

        UtilityClass grade = evaluateGrade(collateral, amount);
        
        WrapperStateStorage(msg.sender, subToken, amount, collateral, grade, true);

        emit AssetWrapped(msg.sender, subToken, amount, grade);
    }

    function WrapperStateStorage(
        address user, 
        address subToken, 
        uint256 amount, 
        uint256 collateral, 
        UtilityClass grade, 
        bool segregated
    ) internal {
        WrappedAsset storage asset = wrapperState[subToken][user];
        asset.amountWrapped += amount;
        asset.collateralReserve += collateral;
        asset.grade = grade;
        asset.isSegregated = segregated;
    }
}
