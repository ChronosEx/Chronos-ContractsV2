// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import './interfaces/IPair.sol';
import './interfaces/IBribe.sol';
import './interfaces/IERC20s.sol';
import './interfaces/IMaArtProxy.sol';
import "./libraries/Math.sol";


contract MaGaugeV2Upgradeable is OwnableUpgradeable, ReentrancyGuardUpgradeable, ERC721EnumerableUpgradeable {
    using SafeERC20 for IERC20;

    bool public isForPair;
    bool public emergency;


    IERC20 public rewardToken;
    IERC20 public _VE;
    IERC20 public TOKEN;

    address public DISTRIBUTION;
    address public internal_bribe;
    address public external_bribe;

    uint public DURATION;
    uint public periodFinish;
    uint public rewardRate;
    uint public lastUpdateTime;
    uint public rewardPerTokenStored;

    uint public fees0;
    uint public fees1;


    string constant public version = "1.0.0";

    uint public tokenId;
    
    mapping(uint => uint) public idRewardPerTokenPaid;
    mapping(uint => uint) public rewards;

    uint public _lpTotalSupply;
    mapping(uint => uint) public _lpBalances;


    event RewardAdded(uint reward);
    event Deposit(address indexed user, uint amount);
    event Withdraw(address indexed user, uint amount);
    event Harvest(address indexed user, uint reward);
    event ClaimFees(address indexed from, uint claimed0, uint claimed1);

    ///@dev right now, this calculates the rewards normally, to implement maturity, we have to have in mind the weight of the tokenId, the total Weight, and the changes those make.
    modifier updateReward(uint _maNFTId) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (_maNFTId != 0) {
            rewards[_maNFTId] = earned(_maNFTId);
            idRewardPerTokenPaid[_maNFTId] = rewardPerTokenStored;
        }
        _;
    }

    modifier onlyDistribution() {
        require(_msgSender() == DISTRIBUTION, "Caller is not RewardsDistribution contract");
        _;
    }

    modifier isNotEmergency() {
        require(emergency == false);
        _;
    }

    constructor() {}

    function initialize(address _rewardToken,address _ve,address _token,address _distribution, address _internal_bribe, address _external_bribe, bool _isForPair) initializer  public {
        __Ownable_init();
        __ReentrancyGuard_init();

        rewardToken = IERC20(_rewardToken);     // main reward
        _VE = IERC20(_ve);                      // vested
        TOKEN = IERC20(_token);                 // underlying (LP)
        DISTRIBUTION = _distribution;           // distro address (voter)
        DURATION = 7 * 86400;                    // distro time

        internal_bribe = _internal_bribe;       // lp fees goes here
        external_bribe = _external_bribe;       // bribe fees goes here

        isForPair = _isForPair;                 // pair boolean, if false no claim_fees

        emergency = false;                      // emergency flag

        //set NFT info:
        bool _stable = IPair(_token).isStable();
        address _token0;
        address _token1;
        (_token0, _token1) = IPair(_token).tokens();

        string memory _name;
        string memory _symbol;

        if(_stable) {
            _name = string(abi.encodePacked('Maturity NFT: Stable ', IERC20s(_token0).symbol(), '/' , IERC20s(_token1).symbol()));
            _symbol = string(abi.encodePacked('maNFT_S-', IERC20s(_token0).symbol() ,'/' ,IERC20s(_token1).symbol()));
        } else {
            _name = string(abi.encodePacked('Maturity NFT: Volatile ', IERC20s(_token0).symbol(), '/' , IERC20s(_token1).symbol()));
            _symbol = string(abi.encodePacked('maNFT_V-', IERC20s(_token0).symbol() ,'/' ,IERC20s(_token1).symbol()));
        }
        __ERC721_init(_name, _symbol);

        tokenId = 1;
        emit Transfer(address(0), address(this), 0); 
    }


    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    ONLY OWNER
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    ///@notice set distribution address (should be voter)
    function setDistribution(address _distribution) external onlyOwner {
        require(_distribution != address(0), "zero addr");
        require(_distribution != DISTRIBUTION, "same addr");
        DISTRIBUTION = _distribution;
    }

    ///@notice set new internal bribe contract (where to send fees)
    function setInternalBribe(address _int) external onlyOwner {
        require(_int >= address(0), "zero");
        internal_bribe = _int;
    }

    function activateEmergencyMode() external onlyOwner {
        require(emergency == false);
        emergency = true;
    }

    function stopEmergencyMode() external onlyOwner {
        require(emergency == false);
        emergency = false;
    }


    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    VIEW FUNCTIONS
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    ///@notice total supply held
    function lpTotalSupply() public view returns (uint) {
        return _lpTotalSupply;
    }

    ///@notice balance of a user
    function lpBalanceOfUser(address account) external view returns (uint amount) {
        uint[] memory tokenIds = tokensOfOwner(account);
        uint len = tokenIds.length;

        for ( uint i; i < len; i++) {
            amount += _lpBalances[tokenIds[i]];
        }
    }
    
    function lpBalanceOfmaNFT(uint _maNFTId) external view returns (uint) {
        return _lpBalances[_maNFTId];
    }

    ///@notice last time reward
    function lastTimeRewardApplicable() public view returns (uint) {
        return Math.min(block.timestamp, periodFinish);
    }

    ///@notice  reward for a single token
    ///@dev If we want to add "maturity" instead of _lpTotalSupply we should use _totalWeight ( having in mind that _totalWeight has changed since last call because of linear increase on maturity)
    function rewardPerToken() public view returns (uint) {
        if (_lpTotalSupply == 0) {
            return rewardPerTokenStored;
        } else {
            return rewardPerTokenStored + ( (lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18 / _lpTotalSupply );
        }
    }

    ///@notice see earned rewards for user
    function earned(uint _maNFTId) public view returns (uint) {
        return (_lpBalances[_maNFTId] * (rewardPerToken() - idRewardPerTokenPaid[_maNFTId]) / 1e18) + rewards[_maNFTId];
    }

    ///@notice get total reward for the duration
    function rewardForDuration() external view returns (uint) {
        return rewardRate * DURATION;
    }

    function _periodFinish() external view returns (uint) {
        return periodFinish;
    }



    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    USER INTERACTION
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */


    ///@notice deposit all LP TOKEN of _msgSender()
    function depositAll() external returns (uint _maNFTId) {
        uint amount = TOKEN.balanceOf(_msgSender());
        TOKEN.safeTransferFrom(_msgSender(), address(this), amount);

        _maNFTId = _deposit(amount, _msgSender());
    }

    ///@notice deposit amount LP TOKEN
    function deposit(uint amount) external returns (uint _maNFTId) {
        TOKEN.safeTransferFrom(_msgSender(), address(this), amount);

        _maNFTId = _deposit(amount, _msgSender());
    }

    ///@notice deposit amount LP TOKEN from msg.sender to _to
    function depositTo(uint amount, address _to) external returns (uint _maNFTId) {
        TOKEN.safeTransferFrom(_msgSender(), address(this), amount);

        _maNFTId = _deposit(amount, _to);
    }

    ///@notice deposit internal
    ///@dev here a mapping should be created to have in mind the time the tokenId was last updated
    ///     and a mapping to know the maturity of this tokenId
    function _deposit(uint amount, address account) internal nonReentrant isNotEmergency updateReward(tokenId) returns (uint _maNFTId){
        require(amount > 0, "deposit(Gauge): cannot stake 0");

        _maNFTId = tokenId;
        _mint(account,_maNFTId);
        tokenId++;

        _lpBalances[_maNFTId] = _lpBalances[_maNFTId] + amount;
        _lpTotalSupply = _lpTotalSupply + amount;

        emit Deposit(account, amount);
    }

    ///@notice withdraw all token
    function withdrawAll() external {
        uint[] memory tokenIds = tokensOfOwner(_msgSender());
        uint len = tokenIds.length;
        for ( uint i; i < len; i++) {
            getReward( tokenIds[i] );
            _withdraw( tokenIds[i] );
        }
    }

    ///@notice withdraw a certain amount of TOKEN
    function withdraw(uint _maNFTId) external {
        getReward( _maNFTId );
        _withdraw( _maNFTId );
    }

    ///@notice withdraw internal
    ///@dev  lastUpdate mapping should update
    ///      maturity mapping should update
    function _withdraw(uint _maNFTId) internal nonReentrant isNotEmergency updateReward(_maNFTId) {
        require(_isApprovedOrOwner(_msgSender(), _maNFTId), "maNFT: caller is not token owner or approved");

        uint amount = _lpBalances[_maNFTId];
        
        require(amount > 0, "Cannot withdraw 0");
        require(_lpTotalSupply - amount >= 0, "supply < 0");

        _lpTotalSupply = _lpTotalSupply - amount;
        _lpBalances[_maNFTId] = _lpBalances[_maNFTId] - amount;

        _burn(_maNFTId);
        
        //Not sure which one to use.
        TOKEN.safeTransfer(_msgSender(), amount);
        //TOKEN.safeTransfer(_ownerOf(_maNFTId), amount);
        emit Withdraw(_msgSender(), amount);
    }

    function emergencyWithdrawAll() external {
        uint[] memory tokenIds = tokensOfOwner(_msgSender());
        uint len = tokenIds.length;
        for ( uint i; i < len; i++) {
            emergencyWithdraw( tokenIds[i] );
        }
    }
    
    function emergencyWithdraw(uint _maNFTId) public nonReentrant {
        require(emergency);
        require(_isApprovedOrOwner(_msgSender(), _maNFTId), "maNFT: caller is not token owner or approved");

        uint _amount = _lpBalances[_maNFTId];

        _lpTotalSupply = _lpTotalSupply - _amount;
        _lpBalances[_maNFTId] = _lpBalances[_maNFTId] - _amount;

        //Not sure which one to use.
        TOKEN.safeTransfer(_msgSender(), _amount);
        //TOKEN.safeTransfer(_ownerOf(_maNFTId), amount);
        emit Withdraw(_msgSender(), _amount);
    }

    /*
    ///@notice withdraw all TOKEN and harvest rewardToken
    function withdrawAllAndHarvest() external {
        uint[] memory tokenIds = tokensOfOwner(_msgSender());
        uint len = tokenIds.length;
        for ( uint i; i < len; i++) {
            getReward();
            _withdraw( tokenIds[i], _lpBalances[tokenIds[i]]);
        }
    }
    */
 
    ///@notice User harvest function called from voter ( voter will only call _maNFTIds from the msg.sender )
    function getRewardFromVoter(uint _maNFTId) public nonReentrant onlyDistribution updateReward(_maNFTId) {

        uint reward = rewards[_maNFTId];
        if (reward > 0) {
            rewards[_maNFTId] = 0;

            
            rewardToken.safeTransfer(_ownerOf(_maNFTId), reward);

            emit Harvest(_ownerOf(_maNFTId), reward);
        }
    }

    ///@notice User harvest function
    function getReward( uint _maNFTId) public nonReentrant updateReward(_maNFTId) {
        require(_isApprovedOrOwner(_msgSender(), _maNFTId), "maNFT: caller is not token owner or approved");

        uint reward = rewards[_maNFTId];
        if (reward > 0) {
            rewards[_maNFTId] = 0;
            
            //Not sure which one to use.
            rewardToken.safeTransfer(_msgSender(), reward);
            //rewardToken.safeTransfer(_ownerOf(_maNFTId), reward);

            emit Harvest(_msgSender(), reward);
            //emit Harvest(_ownerOf(_maNFTId), reward);
        }
    }
    
    ///@notice User harvest all his maNFTs
    function getAllReward() external {
        uint[] memory tokenIds = tokensOfOwner(_msgSender());
        uint len = tokenIds.length;
        for ( uint i; i < len; i++) {
            getReward( tokenIds[i] );
        }
    }








    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    DISTRIBUTION
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */


    /// @notice Receive rewards from distribution
    function notifyRewardAmount(address token, uint reward) external nonReentrant isNotEmergency onlyDistribution updateReward(0) {
        require(token == address(rewardToken));
        rewardToken.safeTransferFrom(DISTRIBUTION, address(this), reward);

        if (block.timestamp >= periodFinish) {
            rewardRate = reward / DURATION;
        } else {
            uint remaining = periodFinish - block.timestamp;
            uint leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / DURATION;
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint balance = rewardToken.balanceOf(address(this));
        require(rewardRate <= balance / DURATION, "Provided reward too high");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + DURATION;
        emit RewardAdded(reward);
    }


    function claimFees() external nonReentrant returns (uint claimed0, uint claimed1) {
        return _claimFees();
    }

     function _claimFees() internal returns (uint claimed0, uint claimed1) {
        if (!isForPair) {
            return (0, 0);
        }
        address _token = address(TOKEN);
        (claimed0, claimed1) = IPair(_token).claimFees();
        if (claimed0 > 0 || claimed1 > 0) {
            uint _fees0 = fees0 + claimed0;
            uint _fees1 = fees1 + claimed1;
            (address _token0, address _token1) = IPair(_token).tokens();

            if (_fees0  > 0) {
                fees0 = 0;
                IERC20(_token0).approve(internal_bribe, 0);
                IERC20(_token0).approve(internal_bribe, _fees0);
                IBribe(internal_bribe).notifyRewardAmount(_token0, _fees0);
            } else {
                fees0 = _fees0;
            }
            if (_fees1  > 0) {
                fees1 = 0;
                IERC20(_token1).approve(internal_bribe, 0);
                IERC20(_token1).approve(internal_bribe, _fees1);
                IBribe(internal_bribe).notifyRewardAmount(_token1, _fees1);
            } else {
                fees1 = _fees1;
            }
            emit ClaimFees(_msgSender(), claimed0, claimed1);
        }
    }







    /*///////////////////////////////////////////////////////////////
                             NFT FUNCTIONS
    //////////////////////////////////////////////////////////////*/


    /// @notice Returns current token URI metadata
    /// @param _maNFTId Token ID to fetch URI for.
    function tokenURI(uint _maNFTId) override public view returns (string memory) {
        _requireMinted(_maNFTId);
        
        return IMaArtProxy(0xB5Fad4D924166a4AC5390B587D27F94dA3fE2Fe8)._tokenURI(_maNFTId);
    }

    function tokensOfOwner(address _owner) public view returns (uint[] memory) {
        uint tokenCount = balanceOf(_owner);
        if (tokenCount == 0) {
            return new uint[](0);
        } else {
            uint[] memory result = new uint[](tokenCount);
            for (uint index; index < tokenCount; index++) {
                result[index] = tokenOfOwnerByIndex(_owner, index);
            }
            return result;
        }
    }
    
    function isApprovedOrOwner(address user, uint _maNFTId) external view returns (bool) {
        return _isApprovedOrOwner(user, _maNFTId);
    }

}