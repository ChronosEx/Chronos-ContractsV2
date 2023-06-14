// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./libraries/BokkyPooBahsRedBlackTreeLibraryFork.sol";

import "./interfaces/IPair.sol";
import "./interfaces/IBribe.sol";
import "./interfaces/IERC20s.sol";
import "./interfaces/IMaArtProxy.sol";
import "./libraries/Math.sol";

contract MaGaugeV2UpgradeableBatchRemove is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC721EnumerableUpgradeable
{
    using SafeERC20 for IERC20;
    using BokkyPooBahsRedBlackTreeLibrary for BokkyPooBahsRedBlackTreeLibrary.Tree;
    using EnumerableSet for EnumerableSet.UintSet;

    bool public isForPair;
    bool public emergency;

    IERC20 public rewardToken;
    IERC20 public _VE;
    IERC20 public TOKEN;

    address public DISTRIBUTION;
    address public internal_bribe;
    address public external_bribe;

    uint private MATURITY_PRECISION;
    uint public DURATION;
    uint private WEIGHTS_MAX_POINTS;
    uint private MAX_SPLIT_WEIGHTS;
    uint private ENTRY_CALCULATION_PRECISION;

    uint private maturityIncrement;
    uint public periodFinish;
    uint public rewardRate;
    uint public lastUpdateTime;
    uint public rewardPerTokenStored;

    uint public fees0;
    uint public fees1;

    string public constant version = "1.0.0";

    uint public tokenId;

    mapping(uint => uint) public idRewardPerTokenPaid;
    mapping(uint => uint) public rewards;

    uint public _lpTotalSupplyPreLimit;
    uint public _lpTotalSupplyPostLimit;

    uint private _totalWeight;
    uint public _lastTotalWeightUpdateTime;
    uint public _weightIncrement;

    mapping(uint => uint) private _lpBalances;
    mapping(uint => uint) public _positionEntries;
    mapping(uint => uint) private _positionLastWeights;

    // red-black tree used for position entries sorting
    BokkyPooBahsRedBlackTreeLibrary.Tree private _preLimitPositionEntriesTree;
    mapping(uint => EnumerableSet.UintSet) private _preLimitEntryToPositionIds;

    event RewardAdded(uint reward);
    event Deposit(address indexed user, uint amount);
    event Withdraw(address indexed user, uint amount);
    event Harvest(address indexed user, uint reward);
    event ClaimFees(address indexed from, uint claimed0, uint claimed1);

    event Split(address indexed user, uint id);
    event Merge(address indexed user, uint fromId, uint toId);
    event Increase(address indexed user, uint id, uint oldAmount, uint newAmount);

    modifier updateTotalWeight() {
        _updateTotalWeight();
        _;
    }

    ///@dev right now, this calculates the rewards normally, to implement maturity, we have to have in mind the weight of the tokenId, the total Weight, and the changes those make.
    modifier updateReward(uint _maNFTId) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (_maNFTId != 0) {
            rewards[_maNFTId] = earned(_maNFTId);
            _positionLastWeights[_maNFTId] = _lpBalances[_maNFTId] * _maturityMultiplier(_maNFTId);
            idRewardPerTokenPaid[_maNFTId] = rewardPerTokenStored;
        }
        _;
    }

    modifier onlyDistribution() {
        require(
            _msgSender() == DISTRIBUTION,
            "Caller is not RewardsDistribution contract"
        );
        _;
    }

    modifier isNotEmergency() {
        require(emergency == false);
        _;
    }

    constructor() {}
    
    function initialize(
        address _rewardToken,
        address _ve,
        address _token,
        address _distribution,
        address _internal_bribe,
        address _external_bribe,
        bool _isForPair
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        rewardToken = IERC20(_rewardToken);     // main reward
        _VE = IERC20(_ve);                      // vested
        TOKEN = IERC20(_token);                 // underlying (LP)
        DISTRIBUTION = _distribution;           // distro address (voter)
        DURATION = 7 * 86400;                   // distro time
        MATURITY_PRECISION = 1e18;
        WEIGHTS_MAX_POINTS = 10000;             // BPS weights, 1 point = 0.01%
        MAX_SPLIT_WEIGHTS = 50;                 // max split weights positions to avoid out of gas
        ENTRY_CALCULATION_PRECISION = 1e18;     // entry calculation precision for merge/increase

        maturityIncrement = 3628800;            // 6 weeks

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

        if (_stable) {
            _name = string(
                abi.encodePacked(
                    "Maturity NFT: Stable ",
                    IERC20s(_token0).symbol(),
                    "/",
                    IERC20s(_token1).symbol()
                )
            );
            _symbol = string(
                abi.encodePacked(
                    "maNFT_S-",
                    IERC20s(_token0).symbol(),
                    "/",
                    IERC20s(_token1).symbol()
                )
            );
        } else {
            _name = string(
                abi.encodePacked(
                    "Maturity NFT: Volatile ",
                    IERC20s(_token0).symbol(),
                    "/",
                    IERC20s(_token1).symbol()
                )
            );
            _symbol = string(
                abi.encodePacked(
                    "maNFT_V-",
                    IERC20s(_token0).symbol(),
                    "/",
                    IERC20s(_token1).symbol()
                )
            );
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

    function totalWeight() external view returns (uint) {
        return _totalWeight;
    }

    function maNFTWeight(uint _maNFTId) external view returns (uint) {
        return _lpBalances[_maNFTId] * _maturityMultiplier(_maNFTId);
    }

    ///@notice total supply held
    function lpTotalSupply() public view returns (uint) {
        return _lpTotalSupplyPreLimit + _lpTotalSupplyPostLimit;
    }

    ///@notice balance of a user
    function lpBalanceOfUser(
        address account
    ) external view returns (uint amount) {
        uint[] memory tokenIds = tokensOfOwner(account);
        uint len = tokenIds.length;

        for (uint i; i < len; i++) {
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
        if (_totalWeight == 0) {
            return rewardPerTokenStored;
        } else {
            return
                rewardPerTokenStored +
                (((lastTimeRewardApplicable() - lastUpdateTime) *
                    rewardRate *
                    1e18) / _totalWeight);
        }
    }

    ///@notice see earned rewards for user
    function earned(uint _maNFTId) public view returns (uint) {
        uint currentPositionWeight = _lpBalances[_maNFTId] * _maturityMultiplier(_maNFTId);
        uint averagePosition = (_positionLastWeights[_maNFTId] + currentPositionWeight) / 2;

        return
            ((averagePosition *
                (rewardPerToken() - idRewardPerTokenPaid[_maNFTId])) / 1e18) /
            MATURITY_PRECISION +
            rewards[_maNFTId];
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
    function depositTo(
        uint amount,
        address _to
    ) external returns (uint _maNFTId) {
        TOKEN.safeTransferFrom(_msgSender(), address(this), amount);

        _maNFTId = _deposit(amount, _to);
    }

    ///@notice deposit internal
    ///@dev here a mapping should be created to have in mind the time the tokenId was last updated
    ///     and a mapping to know the maturity of this tokenId
    function _deposit(
        uint amount,
        address account
    )
        internal
        nonReentrant
        isNotEmergency
        updateTotalWeight
        updateReward(tokenId)
        returns (uint _maNFTId)
    {
        require(amount > 0, "deposit(Gauge): cannot stake 0");

        _maNFTId = tokenId;
        _mint(account, _maNFTId);
        tokenId++;

        uint entry = block.timestamp;

        _addToPosition(_maNFTId, amount, 1 * MATURITY_PRECISION, entry);
        _positionEntries[_maNFTId] = entry;
        
        emit Deposit(account, amount);
    }

    ///@notice withdraw all token
    function withdrawAll() external {
        uint[] memory tokenIds = tokensOfOwner(_msgSender());
        uint len = tokenIds.length;
        for (uint i; i < len; i++) {
            getReward(tokenIds[i]);
            _withdraw(tokenIds[i]);
        }
    }

    ///@notice withdraw a certain amount of TOKEN
    function withdraw(uint _maNFTId) external {
        getReward(_maNFTId);
        _withdraw(_maNFTId);
    }

    ///@notice withdraw internal
    ///@dev  lastUpdate mapping should update
    ///      maturity mapping should update
    function _withdraw(
        uint _maNFTId
    ) internal nonReentrant isNotEmergency updateTotalWeight updateReward(_maNFTId) {
        require(
            _isApprovedOrOwner(_msgSender(), _maNFTId),
            "maNFT: caller is not token owner or approved"
        );

        uint amount = _lpBalances[_maNFTId];

        require(amount > 0, "Cannot withdraw 0");
        require(lpTotalSupply() - amount >= 0, "supply < 0");

       _removeFromPosition(
            _maNFTId,
            amount,
            _maturityMultiplier(_maNFTId),
            _positionEntries[_maNFTId]
        );
        _positionEntries[_maNFTId] = 0;

        _burn(_maNFTId);

        //Not sure which one to use.
        TOKEN.safeTransfer(_msgSender(), amount);
        //TOKEN.safeTransfer(_ownerOf(_maNFTId), amount);
        emit Withdraw(_msgSender(), amount);
    }

    function increase(
        uint _maNFTId,
        uint amount
    ) external nonReentrant isNotEmergency updateTotalWeight updateReward(_maNFTId) {
        require(
            _isApprovedOrOwner(_msgSender(), _maNFTId),
            "maNFT: caller is not token owner or approved"
        );

        TOKEN.safeTransferFrom(_msgSender(), address(this), amount);

        uint oldAmount = _lpBalances[_maNFTId];
        uint oldMultiplier = _maturityMultiplier(_maNFTId);

        uint oldEntry = _positionEntries[_maNFTId];
        uint newEntry = _getNewEntry(oldEntry, block.timestamp, oldAmount, amount);
        _positionEntries[_maNFTId] = newEntry;

        uint newAmount = _lpBalances[_maNFTId] + amount;
        uint newMultiplier = _maturityMultiplier(_maNFTId);

        _addToPosition(_maNFTId, newAmount, newMultiplier, newEntry);
        _removeFromPosition(_maNFTId, oldAmount, oldMultiplier, oldEntry);

        emit Increase(_msgSender(), _maNFTId, oldAmount, newAmount);
    }

    function merge(
        uint _maNFTIdFrom,
        uint _maNFTIdTo
    )
        external
        nonReentrant
        isNotEmergency
        updateTotalWeight
        updateReward(_maNFTIdFrom)
        updateReward(_maNFTIdTo)
    {
        require(
            _isApprovedOrOwner(_msgSender(), _maNFTIdFrom),
            "maNFT: caller is not token owner or approved"
        );
        require(
            _isApprovedOrOwner(_msgSender(), _maNFTIdTo),
            "maNFT: caller is not token owner or approved"
        );

        uint oldAmountTo = _lpBalances[_maNFTIdTo];
        uint oldMultiplierTo = _maturityMultiplier(_maNFTIdTo);
        uint oldEntryTo = _positionEntries[_maNFTIdTo];

        uint newAmountTo = _lpBalances[_maNFTIdTo] + _lpBalances[_maNFTIdFrom];
        uint newEntryTo = _getNewEntry(oldEntryTo, _positionEntries[_maNFTIdFrom], oldAmountTo, _lpBalances[_maNFTIdFrom]);
        _positionEntries[_maNFTIdTo] = newEntryTo;
        uint newMultiplierTo = _maturityMultiplier(_maNFTIdTo);

        _removeFromPosition(
            _maNFTIdFrom,
            _lpBalances[_maNFTIdFrom],
            _maturityMultiplier(_maNFTIdFrom),
            _positionEntries[_maNFTIdFrom]
        );

        _addToPosition(_maNFTIdTo, newAmountTo, newMultiplierTo, newEntryTo);
        _removeFromPosition(
            _maNFTIdTo,
            oldAmountTo,
            oldMultiplierTo,
            oldEntryTo
        );

        _burn(_maNFTIdFrom);
        _positionEntries[_maNFTIdFrom] = 0;
        emit Merge(_msgSender(), _maNFTIdFrom, _maNFTIdTo);
    }

    function split(
        uint _maNFTId,
        uint[] calldata weights
    ) external nonReentrant isNotEmergency updateTotalWeight updateReward(_maNFTId) {
        require(
            _isApprovedOrOwner(_msgSender(), _maNFTId),
            "maNFT: caller is not token owner or approved"
        );

        // limit the weights length to avoid out of gas
        require(weights.length <= MAX_SPLIT_WEIGHTS, "Max splitted positions exceeded");

        uint weightsSum = 0;

        uint positionEntry = _positionEntries[_maNFTId];

        bool preLimit = _maturityMultiplier(_maNFTId) < MATURITY_PRECISION * 3;

        for (uint i; i < weights.length; i++) {
            weightsSum += weights[i];

            uint splitAmount = (weights[i] * _lpBalances[_maNFTId]) / WEIGHTS_MAX_POINTS;
            require(splitAmount > 0, "deposit(Gauge): cannot stake 0");
            uint _newMANFTId = tokenId;
            _mint(_msgSender(), _newMANFTId); // potentially, use ownerOf(_maNFTId)
            tokenId++;

            _lpBalances[_newMANFTId] = splitAmount;
            _positionEntries[_newMANFTId] = positionEntry;

            // track ids if they are pre-limit
            if (preLimit) {
                _preLimitEntryToPositionIds[positionEntry].add(_newMANFTId);
            }
        }

        // bps accuracy is used for e.g.
        require(weightsSum == WEIGHTS_MAX_POINTS, "Invalid weights sum"); 

        if (preLimit) {
            // remove id from ids per entry
            _preLimitEntryToPositionIds[positionEntry].remove(_maNFTId);
            // no need to check if it's the last id by timestamp since splitted ids exist
        }

        // total weight doesn't change as liquidity and maturity didn't change
        _lpBalances[_maNFTId] = 0;
        _positionEntries[_maNFTId] = 0;
        _positionLastWeights[_maNFTId] = 0;

        _burn(_maNFTId);
        
        emit Split(_msgSender(), _maNFTId); // potentially, use owner of nft
    }

    function emergencyWithdrawAll() external {
        uint[] memory tokenIds = tokensOfOwner(_msgSender());
        uint len = tokenIds.length;
        for (uint i; i < len; i++) {
            emergencyWithdraw(tokenIds[i]);
        }
    }

    function emergencyWithdraw(uint _maNFTId) public updateTotalWeight nonReentrant {
        require(emergency);
        require(
            _isApprovedOrOwner(_msgSender(), _maNFTId),
            "maNFT: caller is not token owner or approved"
        );

        uint _amount = _lpBalances[_maNFTId];

        require(_amount > 0, "Cannot withdraw 0");
        require(lpTotalSupply() - _amount >= 0, "supply < 0");

        _removeFromPosition(_maNFTId, _amount, _maturityMultiplier(_maNFTId), _positionEntries[_maNFTId]);

        _burn(_maNFTId);
        _positionEntries[_maNFTId] = 0;

        //Not sure which one to use.
        TOKEN.safeTransfer(_msgSender(), _amount);
        //TOKEN.safeTransfer(_ownerOf(_maNFTId), amount);
        emit Withdraw(_msgSender(), _amount);
    }

    function sync() external {
        _updateTotalWeight();
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
    function getRewardFromVoter(
        uint _maNFTId
    ) public nonReentrant onlyDistribution updateTotalWeight updateReward(_maNFTId) {
        uint reward = rewards[_maNFTId];
        if (reward > 0) {
            rewards[_maNFTId] = 0;

            rewardToken.safeTransfer(_ownerOf(_maNFTId), reward);

            emit Harvest(_ownerOf(_maNFTId), reward);
        }
    }

    ///@notice User harvest function
    function getReward(
        uint _maNFTId
    ) public nonReentrant updateTotalWeight updateReward(_maNFTId) {
        require(
            _isApprovedOrOwner(_msgSender(), _maNFTId),
            "maNFT: caller is not token owner or approved"
        );

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
        for (uint i; i < len; i++) {
            getReward(tokenIds[i]);
        }
    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    HELPER FUNCTIONS
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    function _updateTotalWeight() private {
        // calculate total weight without limit for the pre-limit LP supply
        uint maturityDelta = block.timestamp - _lastTotalWeightUpdateTime;
        _weightIncrement = _weightIncrement + _lpTotalSupplyPreLimit * ((maturityDelta * MATURITY_PRECISION) / maturityIncrement);
        uint totalWeightWithoutLimit = _lpTotalSupplyPreLimit * MATURITY_PRECISION + _weightIncrement;

        // calculate the decrement for this weight for the positions that have reached the limit since last time
        uint totalWeightDecrement = 0;

        uint currentEntry = _preLimitPositionEntriesTree.first();

        uint oldEntry = 0;
        while (currentEntry + 2 * maturityIncrement <= block.timestamp) {
            if (currentEntry == 0) {
                break;
            }

            // process the entry which exceeds max multiplier limit.
            // move its LP to the post-limit LP supply and remove the weight
            // increment for its position from aggregated increment
            for (uint i; i < _preLimitEntryToPositionIds[currentEntry].length(); i++) {
                uint currentId = _preLimitEntryToPositionIds[currentEntry].at(i);

                _lpTotalSupplyPreLimit -= _lpBalances[currentId];
                _lpTotalSupplyPostLimit += _lpBalances[currentId];

                // the weight increment pre-limit introduction should be removed from weight increment
                uint positionWeightIncrement = 
                    _lpBalances[currentId] * _maturityMultiplierNoLimit(currentId) - 
                    _lpBalances[currentId] * MATURITY_PRECISION;

                // the weight of the position is adjusted to the actual recorded increment
                totalWeightDecrement += _lpBalances[currentId] * MATURITY_PRECISION + _reduceWeightIncrement(positionWeightIncrement);
            }

            // move to checking the next entry and cleanup old entry
            oldEntry = currentEntry;
            currentEntry = _preLimitPositionEntriesTree.next(oldEntry);
            delete _preLimitEntryToPositionIds[oldEntry];
        }

        if (oldEntry != 0) {
            _preLimitPositionEntriesTree.removeLeft(oldEntry);
        }

        // calculate total weight
        _totalWeight = totalWeightWithoutLimit + _lpTotalSupplyPostLimit * MATURITY_PRECISION * 3 - totalWeightDecrement;
        _lastTotalWeightUpdateTime = block.timestamp;
    }

    function _maturityMultiplierNoLimit(uint _maNFTId) private view returns (uint) {
        uint maturity = block.timestamp - _positionEntries[_maNFTId];
        return
            MATURITY_PRECISION +
            (maturity * MATURITY_PRECISION) /
            maturityIncrement;
    }

    function _maturityMultiplier(uint _maNFTId) private view returns (uint) {
        uint maturity = block.timestamp - _positionEntries[_maNFTId];
        if (maturity >= 2 * maturityIncrement) return MATURITY_PRECISION * 3;
        else return _maturityMultiplierNoLimit(_maNFTId);
    }

    function _getNewEntry(uint firstEntry, uint secondEntry, uint oldAmount, uint amountIncrement) private view returns(uint) {
        uint olderEntry;
        uint entryDiff;
        if (firstEntry > secondEntry) {
            olderEntry = firstEntry;
            entryDiff = firstEntry - secondEntry;
        } else {
            olderEntry = secondEntry;
            entryDiff = secondEntry - firstEntry;
        }
        uint newEntry = (olderEntry * ENTRY_CALCULATION_PRECISION - entryDiff * amountIncrement * ENTRY_CALCULATION_PRECISION / (oldAmount + amountIncrement)) / ENTRY_CALCULATION_PRECISION;
        return newEntry;
    }

    function _addToPosition(
        uint id,
        uint amount,
        uint multiplier,
        uint entry
    ) private {
        uint weight = amount * multiplier;

        _totalWeight += weight;

        if (multiplier < MATURITY_PRECISION * 3) {
            _weightIncrement =
                _weightIncrement +
                (weight - amount * MATURITY_PRECISION);

            _lpTotalSupplyPreLimit =
                _lpTotalSupplyPreLimit +
                amount;

            // add new entry
            if (!_preLimitPositionEntriesTree.exists(entry)) {
                _preLimitPositionEntriesTree.insert(entry);
            }
            _preLimitEntryToPositionIds[entry].add(id);
        } else {
            _lpTotalSupplyPostLimit += amount;
        }

        _lpBalances[id] += amount;
        // not sure if last weight needs to be updated here or only after rewards calculation
        _positionLastWeights[id] = weight;
    }

    function _removeFromPosition(
        uint id,
        uint amount,
        uint multiplier,
        uint entry
    ) private {
        uint weight = amount * multiplier;

        // due to the possible error in weight increment precision, it's possible sum(position weight)
        // is slightly > total weight. the following processing is to avoid underflow

        if (weight > _totalWeight) {
            _totalWeight -= _totalWeight;
        } else {
            _totalWeight -= weight;
        }

        if (multiplier < MATURITY_PRECISION * 3) {
            _reduceWeightIncrement(weight - amount * MATURITY_PRECISION);
            _lpTotalSupplyPreLimit =
                _lpTotalSupplyPreLimit -
                amount;

            // remove old entry
            _preLimitEntryToPositionIds[entry].remove(id);
            // remove entry from tree if it's the only id
            if (_preLimitEntryToPositionIds[entry].length() == 0) {
                _preLimitPositionEntriesTree.remove(entry);
                delete _preLimitEntryToPositionIds[entry];
            }
        } else {
            _lpTotalSupplyPostLimit -= amount;
        }

        _lpBalances[id] -= amount;
    }

    // due to the possible error in total weight precision, it's possible sum(position weight)
    // is slightly > total weight. the following processing is to avoid underflow
    function _reduceWeightIncrement(uint amount) private returns (uint reduction) {
        if (amount > _weightIncrement) {
            reduction = _weightIncrement;
        } else {
            reduction = amount;
        }
        _weightIncrement -= reduction;
    }


    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    DISTRIBUTION
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    /// @notice Receive rewards from distribution
    function notifyRewardAmount(
        address token,
        uint reward
    ) external nonReentrant isNotEmergency onlyDistribution updateTotalWeight updateReward(0) {
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

    function claimFees()
        external
        nonReentrant
        returns (uint claimed0, uint claimed1)
    {
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

            if (_fees0 > 0) {
                fees0 = 0;
                IERC20(_token0).approve(internal_bribe, 0);
                IERC20(_token0).approve(internal_bribe, _fees0);
                IBribe(internal_bribe).notifyRewardAmount(_token0, _fees0);
            } else {
                fees0 = _fees0;
            }
            if (_fees1 > 0) {
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
    function tokenURI(
        uint _maNFTId
    ) public view override returns (string memory) {
        _requireMinted(_maNFTId);

        return
            IMaArtProxy(0xB5Fad4D924166a4AC5390B587D27F94dA3fE2Fe8)._tokenURI(
                _maNFTId
            );
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

    function isApprovedOrOwner(
        address user,
        uint _maNFTId
    ) external view returns (bool) {
        return _isApprovedOrOwner(user, _maNFTId);
    }
}
