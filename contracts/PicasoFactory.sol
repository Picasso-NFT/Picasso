// contracts/nftclub.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

// import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./NFT721/ONFT721.sol";
import "./operator-filter-registry/src/DefaultOperatorFilterer.sol";

// Share configure
struct TShare {
    address owner;
    uint256 ratioPPM;
}

contract PicasoBase is ONFT721, DefaultOperatorFilterer {
    // Mint price in sale period
    uint256 public _salePrice;

    // Contract owner
    address public factory;

    uint256 public platformBalance;
    uint256 public ownerBalance;

    uint256 private _reserveQuantity;

    // Max number allow to mint
    uint256 public _maxSupply;

    // The tokenId of the next token to be minted.
    uint256 internal _currentIndex;

    // Presale and Publicsale start time
    uint256 public presaleStartTime;
    uint256 public presaleEndTime;
    uint256 public saleStartTime;
    uint256 public saleEndTime;

    // Presale Mintable Number
    uint256 public presaleMaxSupply = 0;
    uint256 public presaleMintedCount = 0;

    // Mint count per address
    mapping(address => uint256) public presaleMintCountByAddress;
    uint256 public presaleMaxMintCountPerAddress;

    mapping(address => uint256) public saleMintCountByAddress;
    uint256 public saleMaxMintCountPerAddress;

    // Platform fee ratio in PPM
    uint256 public platformFeePPM = 0;

    // Is the contract paused
    uint256 public paused = 0;
    
    /**
    u256[0] =>  reserveQuantity
        [1] =>  maxSupply
        [2] =>  presaleMaxSupply
        [3] =>  clubID              (obsoleted)
        [4] =>  presaleStartTime
        [5] =>  presaleEndTime
        [6] =>  saleStartTime
        [7] =>  saleEndTime
        [8] =>  presalePrice        (obsoleted)
        [9] =>  salePrice
        /// How many tokens a wallet can mint
        [10] => presalePerWalletCount
        [11] => salePerWalletCount
        [12] => signature nonce
    */
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 _minGasToTransfer, 
        address _lzEndpoint,
        uint256[] memory u256s
    ) ONFT721(name_, symbol_, _minGasToTransfer, _lzEndpoint) {
        require(u256s[0] + u256s[2] <= u256s[1], "PN:maxSupply");

        // 1. Deplay
        factory = msg.sender;

        _reserveQuantity = u256s[0];
        presaleMaxSupply = u256s[2];
        setPresaleTimes(u256s[4], u256s[5]);
        setSaleTimes(u256s[6], u256s[7]);
        setMintPrice(u256s[9]); 
        _maxSupply = u256s[1];

        transferOwnership(tx.origin);

        /// 2. Reserve tokens for creator
        initReserve(u256s[0]);

        /// 3. Setting mint limit for wallets
        presaleMaxMintCountPerAddress = u256s[10];
        saleMaxMintCountPerAddress = u256s[11];
        unchecked {
            if (presaleMaxMintCountPerAddress == 0) {
                presaleMaxMintCountPerAddress -= 1;
            }
            if (saleMaxMintCountPerAddress == 0) {
                saleMaxMintCountPerAddress -= 1;
            }
        }

        /// 4. Setting platform PPM
        platformFeePPM = PicasoFactory(factory).platformFeePPM();
    }

    function initReserve(uint256 reserveQuantity) private {
        if (reserveQuantity > 0) {
            _mint(tx.origin, reserveQuantity, "", false);
        }
    }

    function getAll() public view returns (uint256[] memory) {
        uint256[] memory u = new uint256[](12);

        u[0] = _reserveQuantity;
        u[1] = _maxSupply;
        u[2] = presaleMaxSupply;
        // u[3] = clubId;   // (obsoleted)
        u[4] = presaleStartTime;
        u[5] = presaleEndTime;
        u[6] = saleStartTime;
        u[7] = saleEndTime;
        // u[8] = 0;       // (obsoleted)
        u[9] = _salePrice;
        // u[10] = presaleMaxMintCountPerAddress;       // Shrink contract size
        // u[11] = saleMaxMintCountPerAddress;          // Shrink contract size

        return (u);
    }

    // Minted token will be sent to minter
    function mint(
        address minter,
        uint256 mint_price,
        uint256 count,
        uint256 sign_deadline,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) public payable whenNotPaused {
        uint256 isPresale = 0;
        uint256 isSale = 0;

        // 0. Check is mintable
        if (block.timestamp < presaleStartTime) {
            // Period: Sale not started
            revert("PN:Not started");
        } else if (
            block.timestamp >= presaleStartTime &&
            block.timestamp < presaleEndTime
        ) {
            // Period: Pre-sale period
            require(msg.value >= mint_price * count, "PN:presale val");
            isPresale = 1;
        } else if (
            block.timestamp >= saleStartTime && block.timestamp <= saleEndTime
        ) {
            // Period: Public sale perild
            require(mint_price == _salePrice, "PN:mint_price");
            require(msg.value >= _salePrice * count, "PN:sale val");
            isSale = 1;
        } else {
            revert("PN:Inval period");
        }

        /// Mint `count` number of tokens
        for (uint256 i = 0; i < count; i++) {
            require(_currentIndex < _maxSupply, "PN:No more");

            if (isPresale == 1) {
                requireMintSign(
                    minter,
                    mint_price,
                    count,
                    sign_deadline,
                    r,
                    s,
                    v
                );

                presaleMintedCount++;
                require(presaleMintedCount <= presaleMaxSupply, "PN:Exceed");

                presaleMintCountByAddress[msg.sender]++;
                require(
                    presaleMintCountByAddress[msg.sender] <=
                        presaleMaxMintCountPerAddress,
                    "PN:addr(A)"
                );
            } else if (isSale == 1) {

                saleMintCountByAddress[msg.sender]++;
                require(
                    saleMintCountByAddress[msg.sender] <=
                        saleMaxMintCountPerAddress,
                    "PN:addr(B)"
                );
            } else {
                revert("PN:NotSalePeriod");
            }

            uint256 currentIndex = _currentIndex;

            _mint(minter, 1, "", false);

            uint256 platformGot = (mint_price * platformFeePPM) / 1e6;
            uint256 ownerGot = mint_price - platformGot;

            platformBalance += platformGot;
            ownerBalance += ownerGot;
            _currentIndex++;
        }


    }

    function collect() public onlyOwner {
        uint256 oBalance = ownerBalance;
        ownerBalance = 0;
        payable(owner()).transfer(oBalance);
    }

    function platformCollect(address to) public onlyFactoryOwner {
        uint256 b = platformBalance;
        platformBalance = 0;
        payable(to).transfer(b);
    }

    /// If signagure is not valid, throw exception and stop
    function requireMintSign(
        address minter,
        uint256 price,
        uint256 count,
        uint256 deadline,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) internal view {
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 userHash = encodeMint(minter, price, count, deadline);
        bytes32 prefixHash = keccak256(abi.encodePacked(prefix, userHash));

        address hash_address = ecrecover(prefixHash, v, r, s);

        require(
            hash_address == PicasoFactory(factory).signerAddress(),
            "PN:sign"
        );
    }

    function encodeMint(
        address minter,
        uint256 price,
        uint256 count,
        uint256 deadline
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(minter, price, count, deadline));
    }

    function _baseURI() internal view override returns (string memory) {
        string memory factoryBaseURI = PicasoFactory(factory).factoryBaseURI();
        return
            string(
                abi.encodePacked(
                    factoryBaseURI,
                    toString(abi.encodePacked(this)),
                    "/"
                )
            );
    }

    // Set the mint price for sale period
    function setMintPrice(uint256 sale_price) public onlyOwner {
        _salePrice = sale_price;
    }

    function setPresaleMaxSupply(uint256 max_) public onlyOwner {
        presaleMaxSupply = max_;
    }

    function setPresaleMaxMintCountPerAddress(uint256 max_) public onlyOwner {
        presaleMaxMintCountPerAddress = max_;
    }

    function setSaleMaxMintCountPerAddress(uint256 max_) public onlyOwner {
        saleMaxMintCountPerAddress = max_;
    }

    function setPresaleTimes(
        uint256 startTime_,
        uint256 endTime_
    ) public onlyOwner {
        presaleStartTime = startTime_;
        if (endTime_ == 0) {
            unchecked {
                presaleEndTime = endTime_ - 1;
            }
        } else {
            presaleEndTime = endTime_;
        }
    }

    function setSaleTimes(
        uint256 startTime_,
        uint256 endTime_
    ) public onlyOwner {
        saleStartTime = startTime_;
        if (endTime_ == 0) {
            unchecked {
                saleEndTime = endTime_ - 1;
            }
        } else {
            saleEndTime = endTime_;
        }
    }

    function setPaused(uint256 is_pause) public onlyOwner {
        paused = is_pause;
    }

    function destroy() public onlyOwner {
        // require(_currentIndex == _reserveQuantity, "PN:notAllow");
        selfdestruct(payable(this.owner()));
    }

    modifier onlyFactoryOwner() {
        PicasoFactory(factory).requireOriginIsOwner();
        _;
    }

    modifier whenNotPaused() {
        require(paused == 0, "PN:paused");
        _;
    }

    function setOpenseaEnforcement(uint256 isEnforcement) public onlyOwner {
        openseaEnforcement = isEnforcement;
    }
}

contract SignAndOwnable is Ownable {
    address public signerAddress;

    constructor() Ownable() {
        signerAddress = tx.origin;
    }

    // Check if the signature is valid. Returns true if signagure is valid, otherwise returns false.
    function verifySignature(
        bytes32 h,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal view returns (bool) {
        return (ecrecover(h, v, r, s) == signerAddress);
    }

    // Set the derived address of the public key of the signer private key
    function setSignaturePublic(address newAddress) public onlyOwner {
        signerAddress = newAddress;
    }
}

contract PicasoFactory is SignAndOwnable {
    uint256 public platformFeePPM = 50 * 1e3;

    string public factoryBaseURI = "";

    mapping(uint256 => uint256) private _usedNonces;

    // Mapping club_id => token_contract_address
    mapping(uint256 => address) public clubMap;

    constructor() SignAndOwnable() {}

    function deploy(
        string memory name_,
        string memory symbol_,
        uint256 _minGasToTransfer, 
        address _lzEndpoint,
        uint256[] memory u256s,
        address[] memory shareAddresses_,
        uint256[] memory shareRatios_,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public returns (address) {
        /// 1. Check signagure
        bytes memory ethereum_prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 user_hash = keccak256(
            abi.encodePacked(
                ethereum_prefix,
                keccak256(abi.encodePacked(u256s[3], u256s[12]))
            )
        );

        require(_usedNonces[u256s[12]] == 0, "PN:DupNonce");
        _usedNonces[u256s[12]] = 1;

        require(verifySignature(user_hash, v, r, s) == true, "PN:invalidSign");

        /// 2. Deploy contract
        PicasoBase c = new PicasoBase(
            name_,
            symbol_,
            _minGasToTransfer,
            _lzEndpoint,
            u256s
        );
        //contracts.push(address(c));
        clubMap[u256s[3]] = address(c);

        return address(c);
    }

    function setPlatformFeePPM(uint256 newFeePPM) public onlyOwner {
        platformFeePPM = newFeePPM;
    }

    /// Set the factoryBaseURI, must include trailing slashes
    function setFactoryBaseURI(string memory newBaseURI) public onlyOwner {
        factoryBaseURI = newBaseURI;
    }

    function requireOriginIsOwner() public view {
        require(tx.origin == owner(), "PN: NotOwner");
    }
}

function toString(bytes memory data) pure returns (string memory) {
    bytes memory alphabet = "0123456789abcdef";

    bytes memory str = new bytes(2 + data.length * 2);
    str[0] = "0";
    str[1] = "x";
    for (uint i = 0; i < data.length; i++) {
        str[2 + i * 2] = alphabet[uint(uint8(data[i] >> 4))];
        str[3 + i * 2] = alphabet[uint(uint8(data[i] & 0x0f))];
    }
    return string(str);
}
