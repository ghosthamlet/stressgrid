import * as _ from 'lodash';
import { action, observable } from 'mobx';

export interface IPlan {
  name?: string;
  state?: string;
  remainingMs?: number;
}

export class RunsStore {
  @observable public runs: { [key: string]: IPlan } = {};

  @action public clear = () => {
    this.runs = {};
  }

  @action public updateRun = (id: string, plan: IPlan) => {
    this.runs[id] = _.assign(_.defaultTo(this.runs[id], {}), plan);
  }

  @action public deleteRun = (id: string) => {
    delete this.runs[id];
  }
}

const store = new RunsStore();
export default store;