// Copyright (c) 2011-2015 The Bitcoin Core developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#include "proposaltablemodel.h"

#include "governance.h"
#include "governance-vote.h"
#include "governance-classes.h"
#include "governance-validators.h"
#include "guiconstants.h"
#include "guiutil.h"
#include "optionsmodel.h"
#include "platformstyle.h"
#include "proposalrecord.h"
#include "masternodeman.h"

#include "core_io.h"
#include "validation.h"
#include "sync.h"
#include "uint256.h"
#include "util.h"

#include <QColor>
#include <QDateTime>
#include <QDebug>
#include <QIcon>
#include <QList>
#include <univalue.h>

#include <boost/foreach.hpp>

static int column_alignments[] = {
        Qt::AlignLeft|Qt::AlignVCenter,
        Qt::AlignRight|Qt::AlignVCenter,
        Qt::AlignRight|Qt::AlignVCenter,
        Qt::AlignRight|Qt::AlignVCenter,
        Qt::AlignRight|Qt::AlignVCenter,
        Qt::AlignRight|Qt::AlignVCenter,
        Qt::AlignRight|Qt::AlignVCenter,
        Qt::AlignRight|Qt::AlignVCenter
    };

ProposalTableModel::ProposalTableModel(const PlatformStyle *platformStyle, QObject *parent):
        QAbstractTableModel(parent),
        platformStyle(platformStyle)
{
    columns << tr("Proposal") << tr("Amount") << tr("Start Date") << tr("End Date") << tr("Yes") << tr("No") << tr("Abs. Yes") << tr("Percentage");

    refreshProposals();
}

ProposalTableModel::~ProposalTableModel()
{
}

void ProposalTableModel::refreshProposals() {
    beginResetModel();
    proposalRecords.clear();

    int mnCount = mnodeman.CountEnabled();

    std::vector<CGovernanceObject*> objs = governance.GetAllNewerThan(0);

    BOOST_FOREACH(CGovernanceObject* pGovObj, objs)
    {
        if(pGovObj->GetObjectType() != GOVERNANCE_OBJECT_PROPOSAL) continue;

        UniValue objResult(UniValue::VOBJ);
        UniValue dataObj(UniValue::VOBJ);
        objResult.read(pGovObj->GetDataAsString());

        std::vector<UniValue> arr1 = objResult.getValues();
        std::vector<UniValue> arr2 = arr1.at( 0 ).getValues();
        dataObj = arr2.at( 1 );

        int percentage = 0;
        if(mnCount > 0) percentage = round(pGovObj->GetAbsoluteYesCount(VOTE_SIGNAL_FUNDING) * 100 / mnCount);
        
        proposalRecords.append(new ProposalRecord(
                        QString::fromStdString(pGovObj->GetHash().ToString()),
                        dataObj["start_epoch"].get_int(),
                        dataObj["end_epoch"].get_int(),
                        QString::fromStdString(dataObj["url"].get_str()),
                        QString::fromStdString(dataObj["name"].get_str()),
                        pGovObj->GetYesCount(VOTE_SIGNAL_FUNDING),
                        pGovObj->GetNoCount(VOTE_SIGNAL_FUNDING),
                        pGovObj->GetAbsoluteYesCount(VOTE_SIGNAL_FUNDING),
                        dataObj["payment_amount"].get_int(),
                        percentage));
    }
    endResetModel();
}

int ProposalTableModel::rowCount(const QModelIndex &parent) const
{
    Q_UNUSED(parent);
    return proposalRecords.size();
}

int ProposalTableModel::columnCount(const QModelIndex &parent) const
{
    Q_UNUSED(parent);
    return columns.length();
}

QVariant ProposalTableModel::data(const QModelIndex &index, int role) const
{
    if(!index.isValid())
        return QVariant();
    ProposalRecord *rec = static_cast<ProposalRecord*>(index.internalPointer());

    switch(role)
    {
    case Qt::DisplayRole:
        switch(index.column())
        {
        case Proposal:
            return rec->name;
        case YesVotes:
            return QVariant::fromValue(rec->yesVotes);
        case NoVotes:
            return QVariant::fromValue(rec->noVotes);
        case AbsoluteYesVotes:
            return QVariant::fromValue(rec->absoluteYesVotes);
        case StartDate:
            return (QDateTime::fromTime_t((qint32)rec->start_epoch)).date().toString(Qt::SystemLocaleLongDate);
        case EndDate:
            return (QDateTime::fromTime_t((qint32)rec->end_epoch)).date().toString(Qt::SystemLocaleLongDate);
        case Percentage:
            return QString("%1\%").arg(rec->percentage);
        case Amount:
            return BitcoinUnits::format(BitcoinUnits::duffs, rec->amount);
        }
        break;
    case Qt::EditRole:
        switch(index.column())
        {
        case Proposal:
            return rec->name;
        case StartDate:
            return rec->start_epoch;
        case EndDate:
            return rec->end_epoch;
        case YesVotes:
            return QVariant::fromValue(rec->yesVotes);
        case NoVotes:
            return QVariant::fromValue(rec->noVotes);
        case AbsoluteYesVotes:
            return QVariant::fromValue(rec->absoluteYesVotes);
        case Amount:
            return qint64(rec->amount);
        case Percentage:
            return QVariant::fromValue(rec->percentage);
        }
        break;
    case Qt::TextAlignmentRole:
        return column_alignments[index.column()];
    case Qt::ForegroundRole:
        if(index.column() == Percentage) {
            if(rec->percentage < 10) {
                return COLOR_NEGATIVE;
            } else {
                return QColor(23, 168, 26);
            }
        } 

        return COLOR_WHITE;
        break;
    case ProposalRole:
        return rec->name;
    case AmountRole:
        return QVariant::fromValue(rec->amount);
    case StartDateRole:
        return rec->start_epoch;
    case EndDateRole:
        return rec->end_epoch;
    case YesVotesRole:
        return QVariant::fromValue(rec->yesVotes);
    case NoVotesRole:
        return QVariant::fromValue(rec->noVotes);
    case AbsoluteYesVotesRole:
        return QVariant::fromValue(rec->absoluteYesVotes);
    case PercentageRole:
        return QVariant::fromValue(rec->percentage);
    case ProposalUrlRole:
        return rec->url;
    case ProposalHashRole:
        return rec->hash;
    }
    return QVariant();
}

QVariant ProposalTableModel::headerData(int section, Qt::Orientation orientation, int role) const
{
    if(orientation == Qt::Horizontal)
    {
        if(role == Qt::DisplayRole)
        {
            return columns[section];
        }
        else if (role == Qt::TextAlignmentRole)
        {
            return Qt::AlignCenter;
        } 
        else if (role == Qt::ToolTipRole)
        {
            switch(section)
            {
            case Proposal:
                return tr("Proposal Name");
            case StartDate:
                return tr("Date and time that the proposal starts.");
            case EndDate:
                return tr("Date and time that the proposal ends.");
            case YesVotes:
                return tr("Obtained yes votes.");
            case NoVotes:
                return tr("Obtained no votes.");
            case AbsoluteYesVotes:
                return tr("Obtained absolute yes votes.");
            case Amount:
                return tr("Proposed amount.");
            case Percentage:
                return tr("Current vote percentage.");
            }
        }
    }
    return QVariant();
}

QModelIndex ProposalTableModel::index(int row, int column, const QModelIndex &parent) const
{
    Q_UNUSED(parent);

    if(row >= 0 && row < proposalRecords.size()) {
        ProposalRecord *rec = proposalRecords[row];
        return createIndex(row, column, rec);
    }

    return QModelIndex();
}