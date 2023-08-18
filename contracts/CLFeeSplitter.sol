// SPDX-License-Identifier: 0BSD
pragma solidity 0.8.13;

import "./interfaces/IVoterV3.sol";
import "./interfaces/IERC20.sol";


interface IDysonVault {
    function pool() external view returns(address);
}

interface IV3pool {
    function token0() external view returns(address);
    function token1() external view returns(address);

    function collectProtocol(
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);
}

interface IBribe {
    function notifyRewardAmount(address _rewardsToken, uint256 reward) external;
}

contract CLFeeSplitter {


    IVoterV3 public voter;
    address public dReceiver;
    address public stakingConverter;

    uint constant public PRECISSION = 10000;
    uint public stakingConverterPercentage;
    uint public dReceiverAmount;

    constructor( address _stakingConverter, address _dAddress, address _voter ) {

        stakingConverter = _stakingConverter;
        dReceiver = _dAddress;
        voter = IVoterV3(_voter);

        stakingConverterPercentage = 2000;
        dReceiverAmount = 600;
    }

    function getFeesAndSend(address[] memory _gauges) external {

        uint len = _gauges.length;

        IV3pool v3pool;
        IDysonVault _dysonVault;

        address _internalBribe;
        IERC20 _token0;
        IERC20 _token1;
        address _gauge;

        uint _amount0;
        uint _amount1;

        for ( uint i; i < len; i++ ) {
            _gauge = _gauges[i];

            _dysonVault = IDysonVault(voter.poolForGauge(_gauge));
            v3pool = IV3pool( _dysonVault.pool() );

            _token0 = IERC20(v3pool.token0());
            _token1 = IERC20(v3pool.token1());

            _internalBribe = voter.internal_bribes(_gauge);

            
            v3pool.collectProtocol(address(this), type(uint128).max, type(uint128).max );

            _amount0 = _token0.balanceOf(address(this));
            _amount1 = _token1.balanceOf(address(this));

            //transfer to Staking Converter:
            _token0.transfer(stakingConverter, _amount0 * stakingConverterPercentage / PRECISSION);
            _token1.transfer(stakingConverter, _amount1 * stakingConverterPercentage / PRECISSION);

            //transfer to dReceiver:
            _token0.transfer(dReceiver, _amount0 * dReceiverAmount / PRECISSION);
            _token1.transfer(dReceiver, _amount1 * dReceiverAmount / PRECISSION);


            //make internal Bribe ( fee bribe )
            _amount0 = _token0.balanceOf(address(this));
            _amount1 = _token1.balanceOf(address(this));
            _token0.approve(_internalBribe, _amount0);
            _token1.approve(_internalBribe, _amount1);

            IBribe(_internalBribe).notifyRewardAmount(address(_token0), _amount0);
            IBribe(_internalBribe).notifyRewardAmount(address(_token1), _amount1);
            
        }
    }
}