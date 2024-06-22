// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelpecConfing.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    address public liquidator = makeAddr("Liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 100 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(liquidator, STARTING_ERC20_BALANCE);
    }

    ////////////////////////
    //Constuctor tests    //
    ////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertIfTokenLengthDoesNotMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressAndPriceFeedAddressMustBeTheSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ////////////////
    // Price Tests //
    /////////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assert(expectedUsd == actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    ////////////////////////
    //depositCollateral tests//
    /////////////////////////

    function testRevertIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock sillyToken = new ERC20Mock("SillyToken", "ST", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(sillyToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetCollateralInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformtion(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
        assertEq(totalDscMinted, expectedTotalDscMinted);
    }

    /////////////////////////////////////
    // depositCollateralAndMintDSC test //
    //////////////////////////////////////

    // This function get the amount to mint at 100% collateralization
    function getAmountToMint(uint256 amountCollateral) private view returns (uint256) {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        return (amountCollateral * (uint256(price) * dsce.getAdditionalFeedPrecision())) / dsce.getPrecision();
    }

    // In this function, the amount of dsc tokens minted are at 100% collateralization; it should break and revert.
    function testMintRevertIfHealthFactorIsBroken() public depositedCollateral {
        vm.startPrank(USER);
        uint256 amountToMint = getAmountToMint(AMOUNT_COLLATERAL);
        vm.expectRevert();
        dsce.mintDSC(amountToMint);
        vm.stopPrank();
    }

    // In this function, the amount of dsc tokens minted are at 400% collateralization; this function must not break
    function testMindAndDepositWorksWith400Overcolateralization() public {
        uint256 amountToMint = getAmountToMint(AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, amountToMint / 4);
        (uint256 totalDscMinted, uint256 actualcollateralValueInUsd) = dsce.getAccountInformtion(USER);
        uint256 expectedCollateralValueInUSD = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        assertEq(totalDscMinted, amountToMint / 4);
        assertEq(expectedCollateralValueInUSD, actualcollateralValueInUsd);
    }

    /////////////////////
    // burnDsc tests   //
    ////////////////////

    function testBurnRevertsAtZero() public {
        uint256 amountToMint = getAmountToMint(AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, amountToMint / 4);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.burnDsc(0);
        vm.stopPrank();
    }

    // here, the user has zero since no deposition or minting has been done
    function testRevertsIfItBurnsMoreThanItHas() public {
        vm.startPrank(USER);
        vm.expectRevert();
        dsce.burnDsc(1);
        vm.stopPrank();
    }

    /////////////////////
    // redeemCollateral test ///
    /////////////////////

    function testRevertIfYouRedeemZero() public depositedCollateral {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateral(weth, 0);
    }

    function testRevertIfYouRedeemMoreThanYouOwn() public depositedCollateral {
        vm.prank(USER);
        vm.expectRevert();
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL * 2);
    }

    function testRedeemCollateralWorks() public depositedCollateral {
        vm.prank(USER);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        uint256 expectedAmountCollateral = 0;
        uint256 actualAmountCollateral = dsce.getAccountCollateralValue(USER);
        assertEq(expectedAmountCollateral, actualAmountCollateral);
    }

    ///////////////////
    // redeemCollateralForDSC test //
    //////////////////

    function testBurnAndRedeemWorks() public {
        uint256 amountToMint = getAmountToMint(AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, amountToMint / 4);
        dsc.approve(address(dsce), amountToMint);
        dsce.redeemCollateralForDSC(weth, AMOUNT_COLLATERAL, amountToMint / 4);
        uint256 expectedAmountCollateral = 0;
        uint256 actualAmountCollateral = dsce.getAccountCollateralValue(USER);
        assertEq(expectedAmountCollateral, actualAmountCollateral);
    }

    ///////////////////////
    // liquidate tests   //
    //////////////////////

    function testLiquateReverseIfDebtToCoverIsZero() public depositedCollateral {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.liquidate(weth, USER, 0);
    }

    function testAttemptLiquidateWithGoodHealthFactor() public {
        uint256 amountToMint = getAmountToMint(AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, amountToMint / 4);
        vm.stopPrank();
        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, amountToMint / 4);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dsce.liquidate(weth, USER, amountToMint / 4);
        vm.stopPrank();
    }
    /**
     * work on get amount to mint; make it in a function that take a value and mint it
     */

    // function testLiquidateWithBadHealthFactor() public {
    //     uint256 amountToMint = getAmountToMint(AMOUNT_COLLATERAL) / 2;
    //     (, int256 priceBefore,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
    //     int256 priceAfter = 1001e8;
    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
    //     dsce.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, amountToMint);
    //     vm.stopPrank();
    //     MockV3Aggregator(ethUsdPriceFeed).updateAnswer(priceAfter);
    //     uint256 ratio = uint256(priceBefore / priceAfter);
    //     uint256 newEthNeeded = (AMOUNT_COLLATERAL * ratio);

    //     vm.startPrank(liquidator);
    //     ERC20Mock(weth).approve(address(dsce), newEthNeeded);
    //     dsce.depositCollateralAndMintDSC(weth, newEthNeeded, amountToMint);
    //     dsce.liquidate(weth, USER, amountToMint);
    //     vm.stopPrank();
    // }

    // (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformtion(USER);
    // assertEq(totalDscMinted, amountToMint - debtToCover);
    // assertEq(collateralValueInUsd, dsce.getUsdValue(weth, AMOUNT_COLLATERAL - newEthNeeded));

    ///////////////////////////
    /// Get functions Testing ///
    /////////////////////////////

    function testGetPrecision() public view {
        assertEq(dsce.getPrecision(), 1e18);
    }

    function testGetAdditionalPrecision() public view {
        assertEq(dsce.getAdditionalFeedPrecision(), 1e10);
    }
}
