const { ethers, upgrades } = require("hardhat")

async function setup() {
    console.log("---")
    let [acc1, acc2] = await ethers.getSigners();

    let _distribution = acc1.address;
    let _internal_bribe = acc2.address;
    let _external_bribe = acc2.address;
    let _isForPair = true;

    // deploy tokens for initialization
    let Token = await ethers.getContractFactory("TestERC20");
    let LPToken = await ethers.getContractFactory("TestPair");

    console.log("Deploying Reward token");
    let deployedReward = await Token.deploy("REWARD", "REWARD");
    let _rewardToken = await deployedReward.deployed();
    console.log("Reward token deployed at " + _rewardToken.address);

    console.log("Deploying VE token");
    let deployedVE = await Token.deploy("VE", "VE");
    let _ve = await deployedVE.deployed();
    console.log("VE token deployed at " + _ve.address);

    // preparing LP token pair
    console.log("Deploying Token1 token");
    let deployedToken1 = await Token.deploy("TOKEN1", "TOKEN1");
    let token1 = await deployedToken1.deployed();
    console.log("Token2 token deployed at " + token1.address);

    console.log("Deploying Token2 token");
    let deployedToken2 = await Token.deploy("TOKEN2", "TOKEN2");
    let token2 = await deployedToken2.deployed();
    console.log("Token2 token deployed at " + token2.address);

    console.log("Deploying LP token");
    let deployedToken = await LPToken.deploy("LP", "LP", token1.address, token2.address);
    let _token = await deployedToken.deployed();
    console.log("LP token deployed at " + _token.address);

    const MaGaugeV2Upgradeable = await ethers.getContractFactory("MaGaugeV2UpgradeableOrderStatistics");
    let maNFTDeployed = await upgrades.deployProxy(
        MaGaugeV2Upgradeable,
        [
            _rewardToken.address,
            _ve.address,
            _token.address,
            _distribution,
            _internal_bribe,
            _external_bribe,
            _isForPair
        ], {
            initializer: 'initialize'
        }
    );

    let maNFT = await maNFTDeployed.deployed();
    console.log("maNFT contract deployed at " + maNFT.address);
    console.log("---")

    return { _token, maNFT };
}

module.exports.setupFunctionalTests = async function() {
    return await setup();
};

module.exports.setupDepositsWeightsTests = async function() {
    return await setup();
};

module.exports.setupHeavyEntriesUpdateTests = async function() {
    return await setup();
};

module.exports.setupAccounts = async function() {
    let [acc1, acc2, acc3, acc4, acc5, acc6, acc7, acc8, acc9, acc10] = await ethers.getSigners();
    return { acc1, acc2, acc3, acc4, acc5, acc6, acc7, acc8, acc9, acc10 };

};