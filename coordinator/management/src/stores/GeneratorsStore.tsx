import * as _ from 'lodash';
import { action, computed, observable } from 'mobx';

export interface IGenerator {
  cpu?: number;
  networkRx?: number;
  networkTx?: number;
  activeCount?: number;
}

export class GeneratorsStore {
  @observable public generators: { [key: string]: IGenerator } = {};
  @observable public desiredSize: number = NaN;

  @action public clear = () => {
    this.generators = {};
  }

  @action public updateGenerator = (id: string, generator: IGenerator) => {
    this.generators[id] = _.assign(_.defaultTo(this.generators[id], {}), generator);
  }

  @action public deleteGenerator = (id: string) => {
    delete this.generators[id];
  }

  @computed get rampStepSize() {
    return _.size(this.generators) * 10;
  }

  @computed get rampSteps() {
    return Math.trunc(this.desiredSize / this.rampStepSize);
  }

  @computed get size() {
    return this.rampSteps * this.rampStepSize
  }
}

const store = new GeneratorsStore();
export default store;