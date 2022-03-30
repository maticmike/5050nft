// contracts/TeamSplit.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract TeamSplit is Ownable{
    IERC20 weth;

    uint256 maintenanceFee;
    uint256 currentWeek;

    address[] wallets;
    address maintenance;
    address marketing;

    mapping(address => bool) private admins;

    AggregatorV3Interface internal priceFeed;

    event ownerPay(uint256 timestamp, uint256 week);
    event emergencyWithdraw(uint256 timestamp, uint256 week);

    /**
     * Network: Mumbai
     * Aggregator: ETH/USD
     * Address: 0x0715A7794a1dc8e42615F059dD6e406A6594651A
     * TestWETH: 0xcBDF8242ec5e8Da18BAF97cB08B7CfDE346aF4bA
     */

    /**
     * Network: Polygon
     * Aggregator: ETH/USD
     * Address: 0xF9680D99D6C9589e2a93a78A04A279e509205945
     * WETH: 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619
     */
    constructor(address _aggregator, address _erc20){
        priceFeed = AggregatorV3Interface(_aggregator);
        weth = IERC20(_erc20);
        admins[msg.sender] = true;
    }

    modifier adminOnly(){
        require(admins[msg.sender], "Not an admin.");
        _;
    }

    function setWallets(address[] memory _wallets, address _maintenance, address _marketing) external onlyOwner{
        wallets = _wallets;
        maintenance = _maintenance;
        marketing = _marketing;
    }

    function setMaintenanceFee(uint256 _price) external onlyOwner{
        maintenanceFee = _price * 10 ** 8;
    }

    function setAdmin(address _address, bool _admin) external onlyOwner{
        admins[_address] = _admin;
    }

    function weeklyPayout() external adminOnly{
        uint256 ethval = ETHPrice(maintenanceFee);

        if(ethval >= weth.balanceOf(address(this))){
            // maintenance always paid
            weth.transfer(maintenance, weth.balanceOf(address(this)));
        }
        else{
            uint256 split = (weth.balanceOf(address(this)) - ethval) / 2;
            uint256 payouts = split / wallets.length;
            bool success;
            // maintenance
            success = weth.transfer(maintenance, ethval);
            require(success, "unsuccessful maintenance transfer");
            // marketing 1/2 of contract value
            success = weth.transfer(marketing, split);
            require(success, "unsuccessful marketing transfer");
            
            // loop through wallets for payouts
            for(uint i=0; i<wallets.length; i++){
                success = weth.transfer(wallets[i],payouts);
                require(success, "unsuccessful wallet transfer");
            }
        }

        emit ownerPay(block.timestamp, currentWeek);
        ++currentWeek;
    }

    // failsafe emergency withdraw
    function withdrawAll() external onlyOwner{
        bool success;
        success = weth.transfer(msg.sender, weth.balanceOf(address(this)));
        require(success, "Unsuccessful transfer");
        emit emergencyWithdraw(block.timestamp, currentWeek);
    }

    // manually set week
    function setWeek(uint256 week) external onlyOwner{
        currentWeek = week;
    }
    
    function ETHPrice(uint256 price) public view returns (uint256) {
        (
            /*uint80 roundID*/,
            int v,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        return 1 ether * price / uint256(v);
    }
}