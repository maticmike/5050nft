// contracts/FiftyFifty.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "./chainlink/VRFConsumerBaseUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

contract FiftyFiftyV2 is Initializable, ERC721EnumerableUpgradeable, VRFConsumerBaseUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using StringsUpgradeable for uint256;
/*
    ███████╗░█████╗░░░░░██╗███████╗░█████╗░  ███╗░░██╗███████╗████████╗
    ██╔════╝██╔══██╗░░░██╔╝██╔════╝██╔══██╗  ████╗░██║██╔════╝╚══██╔══╝
    ██████╗░██║░░██║░░██╔╝░██████╗░██║░░██║  ██╔██╗██║█████╗░░░░░██║░░░
    ╚════██╗██║░░██║░██╔╝░░╚════██╗██║░░██║  ██║╚████║██╔══╝░░░░░██║░░░
    ██████╔╝╚█████╔╝██╔╝░░░██████╔╝╚█████╔╝  ██║░╚███║██║░░░░░░░░██║░░░
    ╚═════╝░░╚════╝░╚═╝░░░░╚═════╝░░╚════╝░  ╚═╝░░╚══╝╚═╝░░░░░░░░╚═╝░░░
*/

    struct Minting{
        uint256 tokenId;
        address minter;
    }

    mapping(uint256 => uint256) public weeklyWinner;
    mapping(uint16 => uint256) public quarterlyWinner;
    mapping(uint8 => uint256) public yearlyWinner;

    mapping(uint256 => mapping(address => uint8)) mintsPerWeek;
    
    mapping(uint16 => uint256) private quarterlyTotal;

    mapping(uint256 => uint8) public tokenToRarity;
    mapping(uint256 => mapping(uint8 => string)) private weeklyRarityURI;
    mapping(uint256 => uint16) private mintQueue;
    mapping(address => bool) private admins;

    mapping(bytes32 => Minting) private responseIdToMint;
    mapping(bytes32 => uint8) private responseIdToAction;

    // for quarterly we'll need to do something like map from quarter -> rarity tier -> uint256 array
    mapping(uint16 => mapping(uint8 => uint256[])) quarterlyToTokenID;
    mapping(uint16 => uint16) quarterlyToWeight;
    
    mapping(uint256 => uint256) public weeklySeed;
    mapping(uint16 => uint256) public quarterlySeed;
    mapping(uint8 => uint256) public yearlySeed;

    mapping(uint256 => uint256) public weeklyPot;

    uint16[] public RARITY;

    // bytes32
    bytes32 private keyHash;

    uint256 public _tokenIds;
    uint256 private fee;
    uint256 private _seed;
    uint256 cost;

    uint256 public currentWeek;
    uint16 public currentQuarter;
    uint8 public currentYear;
    uint8 private _drawType;

    address private ownerAddress;
    address public wethAddress;

    bool public isActive;
    bool public drawingInProgress;

    IERC20Upgradeable weth;

    // Mainnet LINK
    // TOKEN        0xb0897686c545045aFc77CF20eC7A532E3120E0F1
    // Coordinator  0x3d2341ADb2D31f1c5530cDC622016af293177AE0
    // Key Hash     0xf86195cf7690c55907b2b611ebb7343a6f649bff128701cc542f0569e2c549da

    // Mumbai LINK
    // TOKEN        0x326C977E6efc84E512bB9C30f76E30c160eD06FB
    // Coordinator  0x8C7382F9D8f56b33781fE506E897a4F1e2d17255
    // Key Hash     0x6e75b569a01ef56d18cab6a8e71e6600d6ce853834d4a5748b720d06f878b3a4

    // Events

    event WeeklyDraw(address owner, uint256 token, uint256 week, uint256 timestamp);
    event QuarterlyDraw(address owner, uint256 token, uint16 quarter, uint256 timestamp);
    event YearlyDraw(address owner, uint256 token, uint8 year, uint256 timestamp);

    function initialize() initializer public {
        __VRFConsumerBase_init(0x3d2341ADb2D31f1c5530cDC622016af293177AE0, 0xb0897686c545045aFc77CF20eC7A532E3120E0F1);
        __ERC721_init_unchained("50/50 NFT", "5050");
        __ERC721Enumerable_init_unchained();
        __Ownable_init_unchained();
        __ReentrancyGuard_init_unchained();

        // Chainlink Info
        keyHash = 0xf86195cf7690c55907b2b611ebb7343a6f649bff128701cc542f0569e2c549da;
        fee = 0.0001 * 10 ** 18; // 0.0001 LINK

        // 5% ultra rare, 15% rare, 80% common
        RARITY = [500, 1500, 8000];

        cost = .05 ether;

        isActive = false;
        drawingInProgress = false;

    }

/*
    █▀▄▀█ █▀█ █▀▄ █ █▀▀ █ █▀▀ █▀█ █▀
    █░▀░█ █▄█ █▄▀ █ █▀░ █ ██▄ █▀▄ ▄█
*/

    //Modifiers but as functions. Less Gas
    function isPlayer() internal view{    
        uint256 size = 0;
        address acc = msg.sender;
        assembly { size := extcodesize(acc)}
        require((msg.sender == tx.origin && size == 0));
    }

    modifier adminOnly(){
        require(admins[msg.sender], "Not an admin.");
        _;
    }

/*
    ▄▀█ █▀▄ █▀▄▀█ █ █▄░█
    █▀█ █▄▀ █░▀░█ █ █░▀█
*/

    function setActive(bool _active) external onlyOwner{
        isActive = _active;
    }

    function setContractAddresses(address _ownerAddress) external onlyOwner{
        ownerAddress = _ownerAddress;
    }

    function setAdminAddress(address _address, bool _admin) external onlyOwner{
        admins[_address] = _admin;
    }

    function setTokenAddress(address _address) external onlyOwner{
        weth = IERC20Upgradeable(_address);
    }

    function setPrice(uint256 _price) external onlyOwner{
        cost = _price;
    }

    function setBaseURI(uint256 _week, uint8 _rarity, string memory _uri) external onlyOwner{
        weeklyRarityURI[_week][_rarity] = _uri;
    }

    function forceUnstuck(bool _drawingInProgress) external onlyOwner{
        drawingInProgress = _drawingInProgress;
    }

    function setTokenId(uint256 _token) external onlyOwner{
        _tokenIds = _token;
    }

    function setCurrentPeriods(uint256 _currentWeek, uint16 _currentQuarter, uint8 _currentYear) external onlyOwner{
        currentWeek = _currentWeek;
        currentQuarter = _currentQuarter;
        currentYear = _currentYear;
    }

/*
    █▀▀ █░█ ▄▀█ █ █▄░█ █░░ █ █▄░█ █▄▀
    █▄▄ █▀█ █▀█ █ █░▀█ █▄▄ █ █░▀█ █░█
*/

    /**
     * @dev VRF Callback which stores seeds for roll calculation
     * @param requestId of the VRF callback
     * @param randomness the seed passed by chainlink
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        if(responseIdToAction[requestId] == 1){
            Minting storage minting = responseIdToMint[requestId];
            uint8 rare = getRarity(randomness);
            require(minting.minter != address(0), "Minter not set");
            
            tokenToRarity[minting.tokenId] = rare;
            quarterlyToTokenID[currentQuarter][rare].push(minting.tokenId);
            quarterlyToWeight[currentQuarter] += uint16(RARITY.length - rare);

            _mint(minting.minter, minting.tokenId);
            if(mintQueue[currentWeek] > 0){
                mintQueue[currentWeek]--;
            }
        }
        else if(responseIdToAction[requestId] == 2){
            weeklySeed[currentWeek] = randomness;
        }
        else if(responseIdToAction[requestId] == 3){
            quarterlySeed[currentQuarter] = randomness;
        }
        else if(responseIdToAction[requestId] == 4){
            yearlySeed[currentYear] = randomness;
        }

    }

    /**
     * @dev Force fulfill if chainlink fails. We'll pass in the number they tried to pass manually or through oracle.
     */
    function forceFulfillRandomness(bytes32 requestId, uint256 randomness) external onlyOwner {
        if(responseIdToAction[requestId] == 1){
            Minting storage minting = responseIdToMint[requestId];
            uint8 rare = getRarity(randomness);
            require(minting.minter != address(0), "Minter not set");
            
            tokenToRarity[minting.tokenId] = rare;
            quarterlyToTokenID[currentQuarter][rare].push(minting.tokenId);
            quarterlyToWeight[currentQuarter] += uint16(RARITY.length - rare);

            _mint(minting.minter, minting.tokenId);
        }
        else if(responseIdToAction[requestId] == 2){
            weeklySeed[currentWeek] = randomness;
        }
        else if(responseIdToAction[requestId] == 3){
            quarterlySeed[currentQuarter] = randomness;
        }
        else if(responseIdToAction[requestId] == 4){
            yearlySeed[currentYear] = randomness;
        }
    }

/*
    █▀▄▀█ █ █▄░█ ▀█▀ █ █▄░█ █▀▀
    █░▀░█ █ █░▀█ ░█░ █ █░▀█ █▄█
*/

    /**
     * @dev Public minting function.
     * @param qty Up to 10 mints per wallet per weekly period
     */
    function mint(uint8 qty) public nonReentrant{
        isPlayer();
        require(!drawingInProgress, "A drawing is currently taking place, try again in a minute");
        require(ownerAddress != address(0), "Team address is not set");

        if (msg.sender != owner()) {
            require(isActive, "Sale is not active currently.");
            require(mintsPerWeek[currentWeek][msg.sender] + qty <= 10, "Max 10 mints per week per address");
            require(qty > 0 && qty <= 10, "Max 10 per tx");
        }
        
        require(_tokenIds + qty <= getMaxTokens(), "Exceeds max supply for the week");
        require(weth.balanceOf(msg.sender) >= cost * qty, "Insufficient WETH balance");
        uint256 allowance = weth.allowance(msg.sender, address(this));
        require(allowance >= cost*qty, "Check the token allowance");

        // transfer WETH to contract
        uint256 ffsplit = cost * qty * 1/2;
        weth.transferFrom(msg.sender, address(this), ffsplit);
        weth.transferFrom(msg.sender, ownerAddress, ffsplit);

        weeklyPot[currentWeek] += ffsplit;

        bytes32 _requestId;
        mintsPerWeek[currentWeek][msg.sender] += qty;

        mintQueue[currentWeek] += qty;

        for(uint8 i=0; i<qty; i++){
            _requestId = requestRandomness(keyHash, fee);
            responseIdToMint[_requestId] = Minting({tokenId: _tokenIds, minter: msg.sender});
            responseIdToAction[_requestId] = 1;
            _tokenIds++;
        }
    }

/*
    █▀█ █▀▀ ▄▀█ █▀▄   █▀▀ █░█ █▄░█ █▀▀ ▀█▀ █ █▀█ █▄░█ █▀
    █▀▄ ██▄ █▀█ █▄▀   █▀░ █▄█ █░▀█ █▄▄ ░█░ █ █▄█ █░▀█ ▄█
*/
    
    function getRarity(uint256 seed) internal view returns(uint8){
        uint16 rarity;
        uint16 score = uint16(seed % 10000);
        for(uint8 i = 0; i < RARITY.length; i++){
            rarity += RARITY[i];
            if(score >= rarity) continue;
            return i;
        }
        return 2;
    }

    function getRandomTicket(uint16 _quarter, uint256 seed) internal view returns (uint256){
        uint256 cumulative;
        uint256 roll = uint256(keccak256(abi.encode(seed, 1))) % quarterlyToWeight[_quarter];

        for(uint8 i = 0; i < RARITY.length; i++){
            cumulative += (RARITY.length - i) * quarterlyToTokenID[_quarter][i].length;
            if(roll >= cumulative) continue;
            uint256 index = uint256(keccak256(abi.encode(seed, 2))) % quarterlyToTokenID[_quarter][i].length;
            return quarterlyToTokenID[_quarter][i][index];
        }
        revert();
    }

    function getMaxTokens() public view returns(uint256){
        uint256 maxCount = 1000 + (1000*currentWeek);
        return maxCount;
    }

    function getMintsLeft() public view returns(uint256){
        return getMaxTokens() - _tokenIds;
    }

    function getWeeklyURI(uint256 _tokenId) internal view returns(string memory){
        if(_tokenId >= 1000){
            return weeklyRarityURI[_tokenId/1000][tokenToRarity[_tokenId]];
        }
        else{
            return weeklyRarityURI[0][tokenToRarity[_tokenId]];
        }
    }

    function tokenURI(uint256 _tokenId) public view override returns (string memory){
        require(_exists(_tokenId), "ERC721Metadata: URI query for nonexistent token");

        string memory baseURI = getWeeklyURI(_tokenId);
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, _tokenId.toString())) : "";
    }

    function getTokenRarity(uint256 _tokenId) public view returns (string memory){
        require(_exists(_tokenId), "Token does not exist");

        if(tokenToRarity[_tokenId] == 0){
            return "Ultra Rare";
        }
        else if(tokenToRarity[_tokenId] == 1){
            return "Rare";
        }
        else if(tokenToRarity[_tokenId] == 2){
            return "Common";
        }
        else{
            return "What the?";
        }
    }

    /**
     * @dev Returns the wallet of a given wallet. Mainly for ease for frontend devs.
     * @param _wallet The wallet to get the tokens of.
     */
    function walletOfOwner(address _wallet)
        public
        view
        returns (uint256[] memory)
    {
        uint256 tokenCount = balanceOf(_wallet);

        uint256[] memory tokensId = new uint256[](tokenCount);
        for (uint256 i; i < tokenCount; i++) {
            tokensId[i] = tokenOfOwnerByIndex(_wallet, i);
        }
        return tokensId;
    }

/*
    █▀█ ▄▀█ █▀▀ █▀▀ █░░ █▀▀   █▀▀ █░█ █▄░█ █▀▀ ▀█▀ █ █▀█ █▄░█ █▀
    █▀▄ █▀█ █▀░ █▀░ █▄▄ ██▄   █▀░ █▄█ █░▀█ █▄▄ ░█░ █ █▄█ █░▀█ ▄█
*/

    /**
     * @dev Initiate via oracle. Call drawing once seed has been provided by chainlink
     * @param drawType 2 = weekly, 3 = quarterly, 4 = yearly
     */
    function drawingLinkInit(uint8 drawType) external adminOnly{
        require(!drawingInProgress, "Drawing already in progress");

        if(drawType == 2){
            require(mintQueue[currentWeek] == 0, "Mint is pending");
        }
        
        drawingInProgress = true;

        bytes32 _requestId;
        if(drawType >= 2 && drawType <= 3){
            _drawType = drawType;
            _requestId = requestRandomness(keyHash, fee);
            responseIdToAction[_requestId] = drawType;
        }
        else if(drawType == 4){
            require(currentQuarter%4 == 0 && currentQuarter > 0, "4 quarters required for yearly drawing");
            _drawType = 4;
            _drawType = drawType;
            _requestId = requestRandomness(keyHash, fee);
            responseIdToAction[_requestId] = drawType;
        }
        else{
            revert();
        }
    }

    /**
     * @dev Initiate via oracle. If quarterly or annual drawing is going to happen, pause minting via active flag until drawing complete.
     */
    function drawingCall() external adminOnly{
        require(drawingInProgress, "Must call chainlink first");
        if(_drawType == 2){
            weeklyDrawing();

            //increment token id if necessary
            if(_tokenIds < getMaxTokens()){
                _tokenIds = getMaxTokens();   
            }

            currentWeek++;
        }
        else if(_drawType == 3){
            quarterlyDrawing();
            currentQuarter++;
        }
        else if(_drawType == 4){
            yearlyDrawing();
            currentYear++;
        }
        else{
            revert();
        }

        drawingInProgress = false;
        _drawType = 0;
    }

    function weeklyDrawing() internal{
        require(weeklySeed[currentWeek] != 0, "Seed not set");
        require(weth.balanceOf(address(this)) >= weeklyPot[currentWeek], "Contract has insufficient WETH balance");

        uint256 min = 1000*currentWeek;
        uint256 winner = (weeklySeed[currentWeek] % (_tokenIds - min)) + min;
        address currentHolder = ownerOf(winner);

        weth.transfer(currentHolder, weeklyPot[currentWeek]);

        weeklyWinner[currentWeek] = winner;

        emit WeeklyDraw(currentHolder, winner, currentWeek, block.timestamp);
    }

    function quarterlyDrawing() internal{
        require(quarterlySeed[currentQuarter] != 0, "Seed not set");

        uint256 winner = getRandomTicket(currentQuarter, quarterlySeed[currentQuarter]);
        address currentHolder = ownerOf(winner);

        quarterlyWinner[currentQuarter] = winner;

        emit QuarterlyDraw(currentHolder, winner, currentQuarter, block.timestamp);
    }

    function yearlyDrawing() internal{
        require(yearlySeed[currentYear] != 0, "Seed not set");
        require(currentQuarter >= 4, "Too few quarters. Run quarterly drawings first");

        // determine which of the 4 quarters to draw from
        uint16 quarter = (currentQuarter - 4) + uint16(yearlySeed[currentYear] % 4);

        uint256 winner = getRandomTicket(quarter, yearlySeed[currentYear]);
        address currentHolder = ownerOf(winner);

        yearlyWinner[currentYear] = winner;

        emit YearlyDraw(currentHolder, winner, currentYear, block.timestamp);
    }

/*
    █▀█ █▀█ █▀▀ █▄░█ █▀ █▀▀ ▄▀█   █▀█ █░█ █▀▀ █▀█ █▀█ █ █▀▄ █▀▀
    █▄█ █▀▀ ██▄ █░▀█ ▄█ ██▄ █▀█   █▄█ ▀▄▀ ██▄ █▀▄ █▀▄ █ █▄▀ ██▄
*/
    /**
     * Override isApprovedForAll to auto-approve OS's proxy contract
     */
    function isApprovedForAll(address __owner, address _operator)
        public
        view
        override
        returns (bool isOperator)
    {
        // if OpenSea's ERC721 Proxy Address is detected, auto-return true
        if (_operator == address(0x58807baD0B376efc12F5AD86aAc70E78ed67deaE)) {
            return true;
        }

        // otherwise, use the default ERC721.isApprovedForAll()
        return ERC721Upgradeable.isApprovedForAll(__owner, _operator);
    }


    function msgSender()
        internal
        view
        returns (address payable sender)
    {
        if (msg.sender == address(this)) {
            bytes memory array = msg.data;
            uint256 index = msg.data.length;
            assembly {
                // Load the 32 bytes word from memory with the address on the lower 20 bytes, and mask those.
                sender := and(
                    mload(add(array, index)),
                    0xffffffffffffffffffffffffffffffffffffffff
                )
            }
        } else {
            sender = payable(msg.sender);
        }
        return sender;
    }

    function _msgSender()
        internal
        override
        view
        returns (address sender)
    {
        return msgSender();
    }
}
