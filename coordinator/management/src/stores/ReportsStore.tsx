import * as _ from 'lodash';
import { action, observable } from 'mobx';

export interface IReport {
  name: string;
  maxCpu?: number;
  maxNetworkRx?: number;
  maxNetworkTx?: number;
  cwUrl?: string;
  csvUrl?: string;
}

export class ReportsStore {
  @observable public reports: { [key: string]: IReport } = {};

  @action public clear = () => {
    this.reports = {};
  }

  @action public addReport = (id: string, report: IReport) => {
    this.reports[id] = report;
  }

  @action public deleteReport = (id: string) => {
    delete this.reports[id];
  }
}

const store = new ReportsStore();
export default store;