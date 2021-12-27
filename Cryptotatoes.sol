// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-solidity/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "openzeppelin-solidity/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-solidity/contracts/utils/math/SafeMath.sol";

contract TokenAccessControl {
    
    address payable public adminAddress = payable(0xDB7Fdb44105C7A1ee4877E50942a44093984bD65);
    address public puser1Address = payable(0x40284eAFdd374F1057093686A5E9F65c8e0b8018);

    modifier onlyAdmin() {
        require(msg.sender == adminAddress);
        _;
    }

    function setAdmin(address payable _newAdmin) external onlyAdmin {
        require(_newAdmin != address(0));
        adminAddress = _newAdmin;
    }

    function setpuser1(address _newPuser1) external onlyAdmin {
        require(_newPuser1 != address(0));
        puser1Address = _newPuser1;
    }

    modifier onlyPowerUserLevel() {
        require(
            msg.sender == adminAddress ||
            msg.sender == puser1Address
        );
        _;
    }
}

contract FeeControl is TokenAccessControl {
     //FEES
    //fees are applied to minting, breeding, transfers and buying
    //
    uint public mintingFee = 100000000000000000;
    uint public breedingFee = 100000000000000000;
    uint public transferFee = 100000000000000000;
    uint public mutationFee = 100000000000000000;
    uint public buyFeePercentage = 5;

    //SET FEES
    function setMintingFee(uint newFee) external onlyPowerUserLevel() {
        mintingFee = newFee;
    }

    function setBreedingFee(uint newFee) external onlyPowerUserLevel() {
        breedingFee = newFee;
    }

    function setMutationFee(uint newFee) external onlyPowerUserLevel() {
        mutationFee = newFee;
    }

    function setTransferFee(uint newFee) external onlyPowerUserLevel() {
        transferFee = newFee;
    }

    function setBuyFee(uint newFee) external onlyPowerUserLevel() {
        buyFeePercentage = newFee;
    }
}

contract OptionsControl is TokenAccessControl {

    // the first token mint of a wallet is free
    bool public freeFirstTokenMint = true;
    // free mutation mint is enabled, with cooldown mutationMintCooldown
    bool public freeMutationMint = true;
    // uint64 mutation mint cooldown 86400 default seconds
    uint64 public mutationMintCooldown = 60;

    // users can transfer tokens and specials without selling them. Mutation cannot be transferred
    bool public transferEnabled = true;
    //seconds for become adult. Minted tokens and babies have a cooldown to become adults
    uint public secondsToBecomeAdult = 360;

    // published segments -> important for random mutation
    uint public publishedSegments = 8;

    //SET FLAGS
    function setFreeFirstTokenMint(bool b) external onlyPowerUserLevel() {
        freeFirstTokenMint = b;
    }

    function setFreeMutationMint(bool b) external onlyPowerUserLevel() {
        freeMutationMint = b;
    }

    function setMutationMintCooldown(uint64 _seconds) external onlyPowerUserLevel() {
        mutationMintCooldown = _seconds;
    }

    function setTransferEnabled(bool b) external onlyPowerUserLevel() {
        transferEnabled = b;
    }

    function setSecondsToBecomeAdult(uint _seconds) external onlyPowerUserLevel() {
        secondsToBecomeAdult = _seconds;
    }

    function setPublishedSegments(uint _segments) external onlyPowerUserLevel() {
        publishedSegments = _segments;
    }
}

contract Cryptotatoes is ERC721Enumerable, TokenAccessControl, FeeControl, OptionsControl {

    //Events
    event onMintSpecial(address minter, uint256 tokenId);
    event onApplyMutation(address owner, uint256 tokenId, uint256 mutationId);
    event onMintRandomMutation(address minter, uint256 mutationId);

    event onBuy(address buyer, address seller, uint256 tokenId, uint256 price);
    event onMintToken(address minter, uint256 tokenId);
    event onChangePrice(address owner, uint256 tokenId, uint256 newPrice);
    event onTransferToken(address from, address to, uint256 tokenId);
    event onToggleForSale(address owner, uint256 tokenId, bool onSale);
    event onBreedingToken(address owner, uint256 tokenAId, uint256 tokenBId, uint256 babyTokenId);
    event onUpdateURI(uint256 tokenId);

    using Strings for uint256;

    // total number of tokens
    uint256 public maxTokenSupply = 1000000000;
    // total number of specials
    uint256 public maxSpecialSupply = 90000000;
    // total number of specials
    uint256 private initialSpecialCounter = 1000000000;
    // total number of mutations
    uint256 private initialMutationCounter = 10000000000;
    
    // this contract's token collection name
    string public collectionName;
    // this contract's token symbol
    string public collectionNameSymbol;

    // current number of tokens
    uint256 public tokenCounter = 0;
    // total number of specials
    uint256 public specialCounter = initialSpecialCounter;
    // total number of mutations
    uint256 public mutationCounter = initialMutationCounter;

    // Base URI
    string private _baseURIextended;

    //STRUCTS DEFINITIONS

    struct Token {
        uint256 tokenId;                    //index 0
        string tokenName;                   //index 1
        string tokenURI;                    //index 2
        address payable mintedBy;           //index 3
        address payable currentOwner;       //index 4
        uint256 price;                      //index 5
        bool forSale;                       //index 6
        uint256 gene;                       //index 7
        uint256 geneMask;                   //index 8

        // The timestamp from the block when this cat came into existence.
        uint64 birthTime;                   //index 8

        // The minimum timestamp after which this cat can engage in breeding
        // activities again. This same timestamp is used for the pregnancy
        // timer (for matrons) as well as the siring cooldown.
        uint64 cooldownEndTimestamp;            //index 9

        // Set to the index in the cooldown array (see below) that represents
        // the current cooldown duration for this Kitty. This starts at zero
        // for gen0 cats, and is initialized to floor(generation/2) for others.
        // Incremented by one for each successful breeding action, regardless
        // of whether this cat is acting as matron or sire.
        uint16 cooldownIndex;               //index 10
        uint64 lastTimeBreeding;            //index 11
    }

    /*** MAPPING ***/

    // Optional mapping for token URIs
    mapping (uint256 => string) private _tokenURIs;
    // map tokens id to Tokens
    mapping(uint256 => Token) public allTokens;
    // check if token name exists
    mapping(string => bool) public tokenNameExists;
    // check if token URI exists
    mapping(string => bool) public tokenURIExists;
    // minted token by addresses
    mapping (address => uint256) public mintedTokenCount;
    // ultima volta che l'utente ha mintato una mutation
    mapping (address => uint256) public lastTimestampMutationMint;


    /*** CONSTANTS ***/

    /// @dev A lookup table indicating the cooldown duration after any successful
    ///  breeding action, called "pregnancy time" for matrons and "siring cooldown"
    ///  for sires. Designed such that the cooldown roughly doubles each time a cat
    ///  is bred, encouraging owners not to just keep breeding the same cat over
    ///  and over again. Caps out at one week (a cat can breed an unbounded number
    ///  of times, and the maximum cooldown is always seven days).
    uint32[13] private cooldowns = [
        uint32(1 minutes),
        uint32(3 minutes),
        uint32(10 minutes),
        uint32(30 minutes),
        uint32(1 hours),
        uint32(2 hours),
        uint32(4 hours),
        uint32(8 hours),
        uint32(16 hours),
        uint32(1 days),
        uint32(2 days),
        uint32(4 days),
        uint32(7 days)
    ];

    uint256 defaultPrice = 100000000000000000;

    // initialize contract while deployment with contract's collection name and token
    constructor() ERC721("Cryptotatoes Collection", "CPTT") {
        collectionName = name();
        collectionNameSymbol = symbol();
    }

    function getBlockTimestamp() external view returns (uint64) {
        return uint64(block.timestamp);
    }

    function setBaseURI(string memory baseURI_) external onlyAdmin() {
        _baseURIextended = baseURI_;
    }

    function updateUri(uint256 tokenId, string memory _tokenURI) public {
        require(_exists(tokenId), "ERC721Metadata: URI set of nonexistent token");
        address tokenOwner = ownerOf(tokenId);
        //require sender is the owner of the token
        require(msg.sender == tokenOwner);
        //require sender is not 0 address
        require(tokenOwner != address(0));
        //require token is adult ??????????????????????????
        //update uri array
        _tokenURIs[tokenId] = _tokenURI;
        //update token uri
        Token memory token = allTokens[tokenId];
        token.tokenURI = _tokenURI;
        allTokens[tokenId] = token;

        emit onUpdateURI(tokenId);
    }
    
    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal virtual {
        require(_exists(tokenId), "ERC721Metadata: URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
    }
    
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseURIextended;
    }
    
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = _baseURI();
        
        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_tokenURI).length > 0) {
            return string(abi.encodePacked(base, _tokenURI));
        }
        // If there is a baseURI but no tokenURI, concatenate the tokenID to the baseURI.
        return string(abi.encodePacked(base, tokenId.toString()));
    }

    //generate a pseudorandom tokenId in order to randomize the attributes
    function _generateRandomTokenId(uint256 _nonce) internal view returns(uint) {
        return uint(keccak256(abi.encodePacked(_nonce+1, msg.sender, blockhash(block.number - 1))));
    }

    //update cooldownIndex 
    function _triggerCooldown(Token storage _token) internal {
        // Compute an estimation of the cooldown time in blocks (based on current cooldownIndex).
        _token.cooldownEndTimestamp = uint64((cooldowns[_token.cooldownIndex]) + block.timestamp);
        _token.lastTimeBreeding = uint64(block.timestamp);

        // Increment the breeding count, clamping it at 13, which is the length of the
        // cooldowns array. We could check the array size dynamically, but hard-coding
        // this as a constant saves gas. Yay, Solidity!
        if (_token.cooldownIndex < 13) {
            _token.cooldownIndex += 1;
        }
    }

    function getMintedTokensNumber(address _address) public view returns (uint256 count) {
        return mintedTokenCount[_address];
    }

    /*
        A user can mint a mutation, with whom he can edit a specific attribute of a token
    */
    function mintRandomMutation(string memory _name, string memory _mutationURI) public returns (uint256 _mutationId) {
        require(msg.sender != address(0));

        if(freeMutationMint && (lastTimestampMutationMint[msg.sender] == 0 || ((block.timestamp - lastTimestampMutationMint[msg.sender]) > mutationMintCooldown)))
        {
            mutationCounter++;

            // check if a token exists with the above token id => incremented counter
            require(!_exists(mutationCounter));

            // mint the token
            _mint(msg.sender, mutationCounter);
            // set token URI (bind token id with the passed in token URI)
            _setTokenURI(mutationCounter, _mutationURI);
            //update lastTimestampMutationMint array
            lastTimestampMutationMint[msg.sender] = block.timestamp;

            // creat a new mutation (struct) and pass in new values
            Token memory newMutation = Token({
                tokenId: mutationCounter,
                tokenName:_name,
                tokenURI:_mutationURI,
                mintedBy: payable(msg.sender),
                currentOwner: payable(msg.sender),
                price: defaultPrice,
                forSale: false,
                gene: _generateRandomTokenId(mutationCounter),
                geneMask: 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff ^ (0xffff*65536**(uint(keccak256(abi.encodePacked(block.timestamp, msg.sender, mutationCounter))) % publishedSegments)),
                birthTime: uint64(block.timestamp),
                cooldownEndTimestamp: uint64(0),
                cooldownIndex: uint16(0),
                lastTimeBreeding: uint64(0)
            });
            // add the token id and it's mutation to all mutations mapping
            allTokens[mutationCounter] = newMutation;
        }

        emit onMintRandomMutation(msg.sender, mutationCounter );

        return mutationCounter;
    }

    function mintMutation(string memory _name, string memory _mutationURI, uint256 _price, uint256 _mutationGene, uint256 _mutationMask, uint _number) public onlyPowerUserLevel() {
        // check if this function caller is not an zero address account
        require(msg.sender != address(0));

        for(uint i=0; i<_number; i++) {
     
            //uint256 _mutationGene = _generateRandomTokenId(mutationCounter);
            mutationCounter++;
    
            // check if a token exists with the above token id => incremented counter
            require(!_exists(mutationCounter));

            // mint the token
            _mint(msg.sender, mutationCounter);
            // set token URI (bind token id with the passed in token URI)
            _setTokenURI(mutationCounter, _mutationURI);

            // creat a new mutation (struct) and pass in new values
            Token memory newMutation = Token({
                tokenId: mutationCounter,
                tokenName:_name,
                tokenURI:_mutationURI,
                mintedBy: payable(msg.sender),
                currentOwner: payable(msg.sender),
                price: _price,
                forSale: true,
                gene: _mutationGene,
                geneMask: _mutationMask,
                birthTime: uint64(block.timestamp),
                cooldownEndTimestamp: uint64(0),
                cooldownIndex: uint16(0),
                lastTimeBreeding: uint64(0)
            });
            // add the token id and it's mutation to all mutations mapping
            allTokens[mutationCounter] = newMutation;
        }
    } 

    function applyMutation(uint256 _mutationId, uint256 _tokenId) public payable returns(uint256) {
        // check if the function caller is not an zero account address
        require(msg.sender != address(0));
        // require is not special token
        require(_tokenId < maxTokenSupply);
        // require _mutationId is a mutation
        require(_mutationId > initialMutationCounter);
        // check if the mutation id of the mutation and the token exists or not
        require(_exists(_mutationId));
        require(_exists(_tokenId));
        // get the mutation's owner and token's owner
        address mutationOwner = ownerOf(_mutationId);
        address tokenOwner = ownerOf(_tokenId);
        //require owner is the same
        require(mutationOwner == tokenOwner);
        // mutation's owner and token's owner should not be an zero address account
        require(tokenOwner != address(0));
        // mutation's owner and tokens's owner should be the msg.sender
        require(tokenOwner == msg.sender);
        //require price > fee
        require(msg.value >= mutationFee);
        // pay fees to tokens admin
        adminAddress.transfer(mutationFee);

        //save old token gene
        uint256 oldGene = allTokens[_tokenId].gene;
        //extract mutationSegment gene
        uint256 xorMask = allTokens[_mutationId].geneMask ^ 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
        //update token gene
        Token memory token = allTokens[_tokenId];
        token.gene = (allTokens[_tokenId].gene & allTokens[_mutationId].geneMask) | (allTokens[_mutationId].gene & xorMask);
        allTokens[_tokenId] = token;
        //update old Mutation with old gene
        //_setTokenURI(mutationCounter, "");
        Token memory mutation = allTokens[_mutationId];
        mutation.gene = oldGene & xorMask;
        allTokens[_mutationId] = mutation;
        
        onApplyMutation(msg.sender, _tokenId, _mutationId);

        return _mutationId;
    }

    // by a mutation by passing in the mutation's id
    function buy(uint256 _Id) public payable {
        // check if the function caller is not an zero account address
        require(msg.sender != address(0));
        // check if the mutation id of the mutation being bought exists or not
        require(_exists(_Id));
        // get the owner
        address owner = ownerOf(_Id);
        // mutation's owner should not be an zero address account
        require(owner != address(0));
        // the one who wants to buy the mutation should not be the mutation's owner
        require(owner != msg.sender);
        // get that mutation from all mutations mapping and create a memory of it defined as (struct => Mutation)
        Token memory token = allTokens[_Id];
        // price sent in to buy should be equal to or more than the mutation's price
        require(msg.value >= token.price);
        // mutation should be for sale
        require(token.forSale);
        // transfer the mutation from owner to the caller of the function (buyer)
        _transfer(owner, msg.sender, _Id);

        //paga la fee di transfer
        adminAddress.transfer(msg.value*buyFeePercentage/100);

        // get owner of the mutation
        address payable sendTo = payable(owner);
        // send mutation's worth of ethers to the owner
        sendTo.transfer(msg.value - msg.value*buyFeePercentage/100);
        // update the mutation's current owner
        token.currentOwner = payable(msg.sender);
        // update forsale flag
        token.forSale = false;
        // set and update that mutation in the mapping
        allTokens[_Id] = token;

        onBuy(msg.sender,owner,_Id, msg.value);
    }

    function changePrice(uint256 _Id, uint256 _newPrice) public {
        // require caller of the function is not an empty address
        require(msg.sender != address(0));
        // require that token should exist
        require(_exists(_Id));
        // get the token's owner
        address owner = ownerOf(_Id);
        // check that token's owner should be equal to the caller of the function
        require(owner == msg.sender);
        // get that token from all mutations mapping and create a memory of it defined as (struct => Mutation)
        Token memory token = allTokens[_Id];
        // update token's price with new price
        token.price = _newPrice;
        // set and update that token in the mapping
        allTokens[_Id] = token;

        onChangePrice(owner, _Id, _newPrice );
    }

    // switch between set for sale and set not for sale
    function toggleForSale(uint256 _Id) public {
        // require caller of the function is not an empty address
        require(msg.sender != address(0));
        // require that token should exist
        require(_exists(_Id));
        // get the token's owner
        address owner = ownerOf(_Id);
        // check that token's owner should be equal to the caller of the function
        require(owner == msg.sender);
        // get that token from all mutations mapping and create a memory of it defined as (struct => Mutation)
        Token memory token = allTokens[_Id];
        // if token's forSale is false make it true and vice versa
        token.forSale = !token.forSale;
        // set and update that token in the mapping
        allTokens[_Id] = token;
        
        onToggleForSale(owner, _Id, token.forSale);
    }

    /*** TOKEN FUNCTION ***/

    // mint a new token
    function mintToken(string memory _name, string memory _tokenURI) external payable returns (uint256) {
        // check if this function caller is not an zero address account
        require(msg.sender != address(0));
        // max token supply cannot be passed 
        require(tokenCounter < maxTokenSupply);
        // increment counter
        tokenCounter++;
        // check if a token exists with the above token id => incremented counter
        require(!_exists(tokenCounter));
        // check if the token URI already exists or not
        require(!tokenURIExists[_tokenURI]);
        // check if the token name already exists or not
        require(!tokenNameExists[_name]);
        // if freeFirstMint is not enabled, or if freeFirstMint is enabled and the msg.sender already minted a token -> pay minting fee
        if(!freeFirstTokenMint || mintedTokenCount[msg.sender] > 0)
        {
            //tx cost must be greater than mintingFee
            require(msg.value >= mintingFee);
            // pay fees to tokens admin
            adminAddress.transfer(mintingFee);
        }

        // mint the token
        _mint(msg.sender, tokenCounter);
        // set token URI (bind token id with the passed in token URI)
        _setTokenURI(tokenCounter, _tokenURI);

        // update minted tokens counter
        mintedTokenCount[msg.sender]++;

        // make passed token URI as exists
        tokenURIExists[_tokenURI] = true;
        // make token name passed as exists
        tokenNameExists[_name] = true;

        // creat a new token (struct) and pass in new values
        Token memory newToken = Token({
            tokenId: tokenCounter,
            tokenName:_name,
            tokenURI:_tokenURI,
            mintedBy: payable(msg.sender),
            currentOwner: payable(msg.sender),
            price: mintingFee,
            forSale: false,
            gene: _generateRandomTokenId(tokenCounter),
            geneMask: 0,
            birthTime: uint64(block.timestamp - secondsToBecomeAdult + 30),     // -secdondsToBecomeAdult + 100
            cooldownEndTimestamp: uint64(block.timestamp),
            cooldownIndex: uint16(0),
            lastTimeBreeding: uint64(0)
        });
        // add the token id and it's token struct to all tokens mapping
        allTokens[tokenCounter] = newToken;

        //emit event
        onMintToken(msg.sender,tokenCounter);

        return tokenCounter;
    }

    // by a token by passing in the token's id
    function transferToken(uint256 _tokenId, address _recipient) public payable {

        //if transfer is enable or sender is admin
        if(transferEnabled == true || msg.sender == adminAddress) {
            // check if the function caller is not an zero account address
            require(msg.sender != address(0));
            // check if the recipient address is not az zero account address
            require(_recipient != address(0));
            // check if transfers are enabled
            //require(transferEnabled == true);
            // check if the token id of the token being bought exists or not
            require(_exists(_tokenId));
            // get the token's owner
            address tokenOwner = ownerOf(_tokenId);
            // token's owner should not be an zero address account
            //require(tokenOwner != address(0));
            // owner cannot be the recipient
            require(tokenOwner != _recipient);
            // the one who wants to transfer the token should be the token's owner
            require(tokenOwner == msg.sender);

            // require it's a token, standard or special. Mutations cannot be transferred
            require(_tokenId < initialMutationCounter );

            //if transfer is made by a user -> pay fee
            if(msg.sender != adminAddress) {
                // tx cost must be greater than transfer fee 
                require(msg.value>=transferFee);
                // pay the transfer fee to the admin
                adminAddress.transfer(transferFee);
            }

            // transfer the token from owner (= the caller of the function) to the recipient
            _transfer(msg.sender, _recipient, _tokenId);

            // get that token from all tokens mapping and create a memory of it defined as (struct => Tokens)
            Token memory token = allTokens[_tokenId];
            // update current owner of the token
            token.currentOwner = payable(_recipient);
            // set and update that token in the mapping
            allTokens[_tokenId] = token;

            //emit event
            onTransferToken(msg.sender, _recipient, _tokenId);
        }
    }

    function breedTokens(uint256 _tokenIdA, uint256 _tokenIdB, string memory _name, string memory _tokenURI) public payable returns (uint256) {
        
        //mint a new token (random/genetic/other ?)
        
        // require caller of the function is not an empty address
        require(msg.sender != address(0));
        // require tokens ar not special or mutations
        require(_tokenIdA < maxTokenSupply);
        require(_tokenIdB < maxTokenSupply);
        // require that tokens should exist
        require(_exists(_tokenIdA));
        require(_exists(_tokenIdB));
        // get the tokens's ownerships
        address tokenOwnerA = ownerOf(_tokenIdA);
        address tokenOwnerB = ownerOf(_tokenIdB);
        // check that token's owner should be equal to the caller of the function
        require(tokenOwnerA == msg.sender);
        require(tokenOwnerB == msg.sender);

        //get tokens from array of all tokens
        Token storage tokenA = allTokens[_tokenIdA];
        Token storage tokenB = allTokens[_tokenIdB];

        //check compatiblity tokenA and tokenB (male-female)
        //cast uint256 to uint16
        //uint16 firstBitA = uint16 ( uint256 (tokenA.gene & 0x8000000000000000000000000000000000000000000000000000000000000000) >> 255);
        //uint16 firstBitB = uint16 ( uint256 (tokenB.gene & 0x8000000000000000000000000000000000000000000000000000000000000000) >> 255);

        require(uint16 ( uint256 (tokenA.gene & 0x8000000000000000000000000000000000000000000000000000000000000000) >> 255) != uint16 ( uint256 (tokenB.gene & 0x8000000000000000000000000000000000000000000000000000000000000000) >> 255));

        //check breedingcooldowns: at the breeding moment the cooldwons need to be passed
        require(block.timestamp > tokenA.cooldownEndTimestamp);
        require(block.timestamp > tokenB.cooldownEndTimestamp);

        //check tokens cannot be baby: their lifespan (now-birthtime) must be greater than secondsToBecomeAdult Flag
        require(block.timestamp - tokenA.birthTime > secondsToBecomeAdult);
        require(block.timestamp - tokenB.birthTime > secondsToBecomeAdult);

        //tx cost must be greater than breeding fee
        require(msg.value >= breedingFee);

        //pay breeding fee to the admin address
        adminAddress.transfer(breedingFee);

        tokenCounter ++;

        uint256 _tokenId = tokenCounter;

        // check if a token exists with the above token id => incremented counter
        require(!_exists(_tokenId));

        // check if the token URI already exists or not
        require(!tokenURIExists[_tokenURI]);
        // check if the token name already exists or not
        require(!tokenNameExists[_name]);

        // mint the token
        _mint(msg.sender, _tokenId);
        // set token URI (bind token id with the passed in token URI)
        _setTokenURI(_tokenId, "fakeURI");

        // make passed token URI as exists
        tokenURIExists[_tokenURI] = true;
        // make token name passed as exists
        tokenNameExists[_name] = true;

        uint256 _gene = _generateRandomTokenId(tokenCounter);

        // creat a new token (struct) and pass in new values
        Token memory token = Token({
            tokenId: _tokenId,
            tokenName:_name,
            tokenURI:_tokenURI,
            mintedBy: payable(msg.sender),
            currentOwner: payable(msg.sender),
            price: defaultPrice ,
            forSale: false,
            gene: _gene,
            geneMask: 0,
            birthTime: uint64(block.timestamp),
            cooldownEndTimestamp: uint64(block.timestamp),
            cooldownIndex: uint16(0),
            lastTimeBreeding: uint64(0)
        });
        
        // add the token id and it's token to all tokens mapping
        allTokens[_tokenId] = token;

        _triggerCooldown(tokenA);  
        _triggerCooldown(tokenB);

        onBreedingToken(msg.sender, _tokenIdA, _tokenIdB, _tokenId);

        return _tokenId;
    }

    // mint a new Special
    function mintSpecial(string memory _name, string memory _tokenURI, uint256 _price, uint256 _gene) external onlyPowerUserLevel() {
        // check if this function caller is not an zero address account
        require(msg.sender != address(0));

        // la supply non deve essere superata
        require(specialCounter - maxTokenSupply < maxSpecialSupply);

        // increment counter
        specialCounter ++;

        uint256 _specialTokenId = specialCounter;

        // check if a token exists with the above token id => incremented counter
        require(!_exists(_specialTokenId));

        // check if the token URI already exists or not
        require(!tokenURIExists[_tokenURI]);
        // check if the token name already exists or not
        require(!tokenNameExists[_name]);

        // mint the token
        _mint(msg.sender, _specialTokenId);
        // set token URI (bind token id with the passed in token URI)
        _setTokenURI(_specialTokenId, _tokenURI);

        // make passed token URI as exists
        tokenURIExists[_tokenURI] = true;
        // make token name passed as exists
        tokenNameExists[_name] = true;

        // creat a new special (struct) and pass in new values
        Token memory newToken = Token({
            tokenId: _specialTokenId,
            tokenName:_name,
            tokenURI:_tokenURI,
            mintedBy: payable(msg.sender),
            currentOwner: payable(msg.sender),
            price: _price,
            forSale: false,
            gene: _gene,
            geneMask: 0,
            birthTime: uint64(block.timestamp),
            cooldownEndTimestamp: uint64(block.timestamp),
            cooldownIndex: uint16(0),
            lastTimeBreeding: uint64(0)
        });
        // add the special id and it's special to all specials mapping
        allTokens[_specialTokenId] = newToken;

        onMintSpecial(msg.sender,_specialTokenId);
    }
}